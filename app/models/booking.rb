class Booking < ApplicationRecord
  STATUSES = %w[active awaiting_return returned cancelled disputed].freeze

  # Stored in `destination` when the driver would rather not say where they are
  # going. A real value so the field stays required and the calendar has
  # something to show, rather than an ambiguous blank.
  PRIVATE_DESTINATION = "Privat".freeze

  # Older spellings of the marker, still read as private on existing bookings.
  LEGACY_PRIVATE_DESTINATIONS = ["Ikke din sag", "None of your business"].freeze

  def private_destination?
    destination == PRIVATE_DESTINATION || LEGACY_PRIVATE_DESTINATIONS.include?(destination)
  end

  # Bookings originally booked for at least this long are exempt from the
  # shorten penalty — cutting a multi-day trip short is free. Fixed, not a rule.
  PENALTY_FREE_OVER = 24.hours

  belongs_to :user
  belongs_to :resource
  belongs_to :booking_period, optional: true
  # Set only when the trip was made on behalf of a work or interest group.
  belongs_to :billing_group, optional: true
  has_one :billing_transaction, class_name: "Transaction", dependent: :restrict_with_error
  has_many :booking_accessories, dependent: :destroy
  has_many :accessories, through: :booking_accessories, source: :accessory
  belongs_to :parent_booking, class_name: "Booking", optional: true
  has_many :accessory_bookings, class_name: "Booking", foreign_key: :parent_booking_id, dependent: :destroy

  validates :start_at, presence: true
  validates :end_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :destination, presence: true, on: :create, if: -> { resource&.tracks_mileage? && parent_booking_id.nil? }
  validate :end_at_after_start_at
  validate :no_overlapping_bookings
  validate :billing_group_is_permitted
  validate :within_booking_horizon, on: :create
  validate :not_held_for_regular_user, on: :create
  validate :within_home_car_limit, on: :create
  validate :not_in_the_past, if: :from_booking_form

  # Set true by controllers when an admin is the one creating the booking, so the
  # booking horizon (a member-facing limit) doesn't block admin exceptions.
  attr_accessor :creating_admin

  # Set when an admin moves a billed trip onto a group (ReservationTransferService).
  # They may charge any group, whether or not the driver is a member of it.
  attr_accessor :group_set_by_admin

  # Set by the booking form's create/update. Only a member typing a start time
  # is held to "not in the past"; trips the system itself writes (scans,
  # corrections, imports) legitimately carry past times.
  attr_accessor :from_booking_form

  # How far back a member may still start a booking: the half-hour slot already
  # under way, so "now" at 10:12 can be booked from 10:00.
  PAST_START_SLACK = 30.minutes

  scope :active, -> { where(status: "active") }
  scope :awaiting_return, -> { where(status: "awaiting_return") }
  scope :upcoming, -> { active.where("start_at > ?", Time.current) }
  scope :for_resource, ->(resource) { where(resource: resource) }

  def active?
    status == "active"
  end

  def cancellable?
    status == "active"
  end

  # Admins can also cancel a trip that has already been checked out, because they
  # are the ones untangling a mess after the fact — a booking made for the wrong
  # day, a duplicate created while the original was invisible. A member may only
  # cancel a trip they have not started.
  def cancellable_by?(actor)
    return false unless actor
    return true if cancellable? && (user_id == actor.id || actor.admin?)
    actor.admin? && status == "awaiting_return"
  end

  # An admin may remove a booking outright only while nothing has been billed for
  # it. Once there is a transaction the booking is part of the accounts and must
  # be cancelled or corrected, never erased.
  def deletable_by?(actor)
    actor&.admin? && billing_transaction.nil? && status != "returned"
  end

  # A mileage-tracked trip has been started at the vehicle (odometer recorded).
  def checked_in?
    checked_in_at.present?
  end

  # Cars must be checked in (start odometer recorded) before they can be ended —
  # unless the resource type's rules turn that requirement off.
  #
  # Never once the booked time is over: a trip past its end is being returned,
  # not started, and starting it at the current reading would zero its distance.
  def needs_check_in?(time = Time.current)
    resource&.tracks_mileage? && status == "active" && !checked_in? && rules.require_odometer? &&
      time <= end_at
  end

  # Whether `time` falls inside the booked window widened by the type's
  # early-checkout and late-return buffers.
  def window_open_at?(time = Time.current)
    (start_at - rules.checkout_buffer_minutes.minutes) <= time &&
      time <= (end_at + rules.return_buffer_minutes.minutes)
  end

  # Whether the driver can act on this booking (check out / return) at `time`.
  #
  # A trip past its return time but still open stays actionable, so a driver
  # who gets back late can always close it.
  def actionable_at?(time = Time.current)
    return false unless open?
    return true if time > end_at

    window_open_at?(time)
  end

  # Still out: the trip has not been ended, whether or not it is past its time.
  def open?
    completed_at.nil? && %w[active awaiting_return].include?(status)
  end

  def rules
    BookingRules.for(resource&.resource_type)
  end

  def display_name
    payer.presence || user.name
  end

  def hours
    ((end_at - start_at) / 1.hour.to_f).round(1)
  end

  # Hours actually billed. Prorated down when returned early (completed_at before
  # the booked end); never surcharged above the booked window for a late return.
  # Falls back to the full booked duration when not yet completed. A shorten
  # penalty (billed_until) raises the floor: the driver is billed at least to that
  # time even if they return sooner — see #apply_edit_penalty!.
  # Billing is in half-hour blocks with a grace (BookingRules#grace_minutes) on
  # each block: with grace 10, a return at 11:44 on a 10:00 start is billed to
  # 12:00, but one at 11:38 is billed to 11:30.
  BILLING_INCREMENT = 30.minutes

  def billed_hours
    effective_end = end_at

    if completed_at
      if completed_at < end_at
        # Returned early — bill only the time actually used.
        effective_end = completed_at
      elsif completed_at > end_at + rules.grace_minutes.minutes
        # Returned late beyond the grace period — bill the extra time too, or the
        # car would be held past its slot for free. Inside the grace it stays at
        # the booked end, so a couple of minutes late costs nothing.
        effective_end = completed_at
      end
    end

    effective_end = [effective_end, billed_until].max if billed_until
    elapsed = [(effective_end - start_at), 0].max

    # Round the *duration* (not the return time) to whole half-hour blocks, so
    # this stays correct when a booking does not start on a half-hour boundary.
    hours = billed_blocks(elapsed) * (BILLING_INCREMENT / 1.hour.to_f)

    # An early return never costs more than the booked window, or the shorten
    # penalty floor if that is later.
    if completed_at && completed_at < end_at
      ceiling_seconds = [(end_at - start_at), (billed_until ? billed_until - start_at : 0)].max
      hours = [hours, [ceiling_seconds / 1.hour.to_f, 0].max].min
    end

    hours.round(2)
  end

  # The moment this booking is billed until — what a receipt should show as the
  # effective return time, after the half-hour rounding above.
  def billed_until_time
    start_at + billed_hours.hours
  end

  # Still out and past its return time (plus the type's grace) — flagged red in
  # the calendar. False once returned or cancelled.
  def overdue?(now = Time.current)
    return false unless %w[active awaiting_return].include?(status)
    return false if completed_at.present?
    now > end_at + rules.overdue_after_minutes.minutes
  end

  def days
    ((end_at - start_at) / 1.day.to_f).ceil
  end

  def km_driven
    return nil unless start_mileage && end_mileage
    end_mileage - start_mileage
  end

  # Which rate this trip is charged at. A booking made on behalf of a group is
  # charged at the group's rate, not at the rate of whoever drove. Otherwise it
  # falls back to the person's own category.
  #
  # This is the one place that decision is made, so the price the member sees,
  # the amount deducted, and the accounting sheet can never disagree.
  def effective_billing_category
    billing_group&.billing_category || user&.billing_category
  end

  # Who this trip is billed to, for the accounting sheet.
  def billed_to
    billing_group&.name.presence || user&.name.presence || "?"
  end

  def on_behalf_of_group?
    billing_group_id.present?
  end

  # Whether this trip is settled through the member's personal ledger, or billed
  # on the monthly sheet instead (invoiced people, and every group). Shared by
  # completion and correction; uncategorised trips fall back to bank transfer.
  def collected_via_ledger?
    collection = (effective_billing_category || BillingCategory.default)&.collection
    (collection || "bank") == "bank"
  end

  # The rate this trip is charged at, given a freshly computed base. The single
  # place completion and correction agree on how a category is applied.
  def billing_rate_for(base_total:, km:)
    BillingRate.apply(category: effective_billing_category, base_total: base_total, km: km)
  end

  # The group this trip is charged to, shown wherever someone needs to see at a
  # glance who is paying — nil when the driver pays for it themselves.
  def payer_label
    billing_group&.name.presence
  end

  # The rate applied to this trip's charge, as frozen at completion.
  def billing_rate_struct
    BillingRate.from_stored(billing_rate)
  end

  # The itemized charges actually billed at completion, as a Breakdown — or nil
  # for bookings completed before this was stored. Line items sum to total_amount.
  def charge_breakdown_struct
    return nil if charge_breakdown.blank?
    PricingCalculator::Breakdown.new(
      time_cost:      BigDecimal(charge_breakdown["time_cost"].to_s),
      km_cost:        BigDecimal(charge_breakdown["km_cost"].to_s),
      toll_cost:      BigDecimal(charge_breakdown["toll_cost"].to_s),
      accessory_cost: BigDecimal(charge_breakdown["accessory_cost"].to_s)
    )
  end

  def cancel!(reason: nil)
    update!(status: "cancelled", cancellation_reason: reason)
    accessory_bookings.where(status: "active").find_each do |ab|
      ab.update!(status: "cancelled", cancellation_reason: "Parent booking cancelled")
    end
  end

  def accessory_booking?
    parent_booking_id.present?
  end

  # Run a create/update while holding a row lock on the resource, so the overlap
  # check and the write are atomic and two simultaneous requests for the same
  # slot cannot both pass validation.
  def with_resource_lock(&block)
    return block.call if resource.nil?
    resource.with_lock(&block)
  end

  # The latest time this booking may be extended to before it would collide with
  # the next reservation on the same resource — i.e. the start of the earliest
  # live booking that begins at or after this one ends. nil when the road ahead is
  # clear, meaning there is no ceiling. Adjacency is allowed (a booking may extend
  # right up to the next one's start), matching the strict overlap check.
  def max_extension_end
    Booking.where(resource_id: resource_id, status: %w[active awaiting_return])
           .where.not(id: id)
           .where("start_at >= ?", end_at)
           .minimum(:start_at)
  end

  # Recompute the shorten penalty after an edit changed the end time. Called with
  # the end time as it was *before* the edit. Sets billed_until (the billing
  # floor) when an in-progress, short, time-billed booking is shortened; clears it
  # when the booking is re-extended past the floor. No-op otherwise.
  #
  # Rules applied:
  #  • in-progress only — the trip has started (start_at <= now)
  #  • short only — originally booked under PENALTY_FREE_OVER (long trips are free)
  #  • time-billed only — km/state-rate trips have no time component to floor
  #  • penalty hours come from the resource type's rules (0 = disabled)
  # The floor is capped at the original end (shortening never costs more than the
  # booking did) and never lowered below an existing floor (can't dodge by
  # shortening again).
  def apply_edit_penalty!(previous_end:)
    return if previous_end.nil? || end_at.nil?

    # Re-extended back past the floor → the penalty is moot, clear it.
    if end_at > previous_end
      update_column(:billed_until, nil) if billed_until && end_at >= billed_until
      return
    end
    return if end_at == previous_end                                   # not a shortening
    return unless status == "active" && start_at <= Time.current       # in-progress only
    return if (previous_end - start_at) >= PENALTY_FREE_OVER           # long booking: free
    return if effective_billing_category&.per_km?                      # distance-billed: no time penalty

    hours = rules.edit_shorten_penalty_hours
    return if hours <= 0                                               # disabled for this type

    proposed = [end_at + hours.hours, previous_end].min               # cap at the original end
    floor    = [proposed, billed_until].compact.max                   # never lower an existing floor
    update_column(:billed_until, floor)
  end

  private

  # Whole half-hour blocks for `elapsed` seconds. The minutes into a started
  # block are forgiven up to the grace and round up from the minute after it
  # (grace 10: 1h40m bills 2h, 1h40m59s still bills 1.5h). Never under one block.
  def billed_blocks(elapsed)
    block = BILLING_INCREMENT.to_i
    full  = (elapsed / block).floor
    extra = ((elapsed - full * block) / 60).floor
    full += 1 if extra > rules.grace_minutes
    [full, 1].max
  end

  def end_at_after_start_at
    return unless start_at && end_at
    errors.add(:end_at, "must be after start time") if end_at <= start_at
  end

  # Charging a group is restricted to its members. Enforced here rather than only
  # in the form, so a crafted request cannot get round it.
  def billing_group_is_permitted
    return if billing_group.nil? || user.nil?
    return if group_set_by_admin
    return if user.may_book_for?(billing_group)
    errors.add(:billing_group, :not_a_member)
  end

  # Backs up the form, which a stale page or an edited date field can get past.
  # Admins may backdate on purpose, e.g. to record a trip after the fact. On edit
  # only a *moved* start is checked, so a trip under way can still change its end.
  def not_in_the_past
    return if creating_admin || parent_booking_id.present? || start_at.nil?
    return if persisted? && !will_save_change_to_start_at?
    return if start_at >= Time.current - PAST_START_SLACK

    errors.add(:start_at, :in_the_past)
  end

  # Members can only book so far ahead (SiteSetting.booking_horizon_days). Admins
  # bypass it, and accessory shadow-bookings inherit their parent's window so they
  # are never independently blocked.
  def within_booking_horizon
    return if creating_admin || parent_booking_id.present?
    return unless start_at

    horizon = SiteSetting.instance.booking_horizon_date
    return if horizon.nil? || start_at.to_date <= horizon

    errors.add(:start_at, :beyond_horizon, date: horizon.strftime("%-d/%-m %Y"))
  end

  # A car is held for its fast bruger during their working hours (see
  # Resource#held_for?). Admins bypass; accessory shadow-bookings inherit.
  def not_held_for_regular_user
    return if creating_admin || parent_booking_id.present?
    return unless resource && start_at && end_at

    if resource.held_for?(start_at, end_at, user)
      errors.add(:base, I18n.t("bookings.alerts.reserved_for_regular_user", name: resource.regular_driver_name))
    end
  end

  # Home cars are meant for short local trips, so they carry their own maximum
  # booking length (SiteSetting.home_car_max_hours). Admins bypass.
  def within_home_car_limit
    return if creating_admin || parent_booking_id.present?
    return unless resource&.home_car? && start_at && end_at

    limit = SiteSetting.instance.home_car_max_hours_limit
    return if limit.nil? || hours <= limit

    errors.add(:base, I18n.t("bookings.alerts.home_car_too_long", hours: limit))
  end

  def no_overlapping_bookings
    return unless resource && start_at && end_at

    overlapping = Booking.where(resource: resource)
      .where(status: %w[active awaiting_return])
      .where("start_at < ? AND end_at > ?", end_at, start_at)

    overlapping = overlapping.where.not(id: id) if persisted?

    max_concurrent = resource.inventory_count || 1
    if overlapping.count >= max_concurrent
      errors.add(:base, I18n.t("bookings.alerts.overlap"))
    end
  end
end
