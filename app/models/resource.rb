class Resource < ApplicationRecord
  STATUSES = %w[active unavailable retired].freeze

  belongs_to :resource_type
  belongs_to :regular_user, class_name: "User", optional: true
  has_many :resource_prices, dependent: :destroy
  has_many :pricing_rules, dependent: :destroy
  has_one :resource_stat, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error
  has_many :resource_compatibilities, dependent: :destroy
  has_many :accessories, through: :resource_compatibilities, source: :accessory
  has_many :inverse_compatibilities, class_name: "ResourceCompatibility", foreign_key: :accessory_id, dependent: :destroy
  has_many :compatible_with, through: :inverse_compatibilities, source: :resource

  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :qr_token, uniqueness: true, allow_nil: true

  before_create :ensure_qr_token

  # Running odometer for the vehicle. Source of truth for start mileage, stored on
  # the resource's stat record (jsonb). ReservationCompletionService reads this as the
  # start reading and writes the new reading back on completion.
  def current_odometer
    resource_stat&.mileage
  end

  def current_odometer=(value)
    (resource_stat || build_resource_stat).mileage = value
  end

  # Replaces the token (revocation / lost-sticker). Also the mechanism the admin
  # regenerate button calls.
  def regenerate_qr_token!
    update!(qr_token: self.class.generate_unique_qr_token)
  end

  def self.generate_unique_qr_token
    loop do
      token = SecureRandom.urlsafe_base64(32) # 43 url-safe chars
      break token unless exists?(qr_token: token)
    end
  end

  def display_name
    if resource_type&.tracks_mileage?
      parts = [port, color, make].compact_blank
      parts.any? ? parts.join(" ") : name
    else
      name
    end
  end

  scope :active, -> { where(status: "active") }
  scope :bookable, -> { where(status: "active") }
  # Cars — mileage-tracked resources, the only ones the minimum-price rule and the
  # home-car flag apply to.
  scope :cars, -> { joins(:resource_type).where(resource_types: { billing_type: "per_day_and_km" }).order(:name) }

  def car?
    resource_type&.billing_type == "per_day_and_km"
  end

  def active?
    status == "active"
  end

  def unavailable?
    status == "unavailable"
  end

  def retired?
    status == "retired"
  end

  def price_for(user_type)
    explicit_price_for(user_type) || default_price_for(user_type)
  end

  # This resource's own price, if it has been set on the vehicle itself.
  def explicit_price_for(user_type)
    if user_type == "employee" && resource_type&.name != "Toll"
      resident_price = resource_prices.find_by(user_type: "resident")
      return nil unless resident_price
      # Employee pays 2x resident rate — build a virtual price object
      ResourcePrice.new(
        resource: self,
        user_type: "employee",
        hour_rate: resident_price.hour_rate * 2,
        day_rate: resident_price.day_rate * 2,
        km_rate: resident_price.km_rate * 2,
        min_charge: resident_price.min_charge * 2,
        day_cap_hours: resident_price.day_cap_hours
      )
    else
      # Resident rate, or Toll (same for everyone)
      resource_prices.find_by(user_type: "resident") || resource_prices.find_by(user_type: user_type)
    end
  end

  # Falls back to the resource type's default hourly rate when the vehicle has no
  # price of its own, so a new car costs 5 kr/hour without setting anything.
  def default_price_for(user_type)
    hour = resource_type&.default_hour_rate_for(user_type)
    return nil if hour.nil?

    ResourcePrice.new(resource: self, user_type: user_type,
                      hour_rate: hour, day_rate: 0, km_rate: 0, min_charge: 0, day_cap_hours: 16)
  end

  def tracks_mileage?
    resource_type.tracks_mileage?
  end

  def electric?
    electric
  end

  def recharging?
    recharge_until.present? && recharge_until > Time.current
  end

  # The booking that most recently had this vehicle before `before` — the
  # "previous user". Used so a member can see the last trip's distance (to judge
  # remaining charge) and contact whoever had it. Completed trips are included so
  # km_driven is available.
  def previous_booking(before: Time.current)
    bookings.where(status: %w[returned active awaiting_return], parent_booking_id: nil)
            .where("start_at <= ?", before)
            .order(start_at: :desc)
            .first
  end

  # The next reservation starting after `after` — the "next user", so a member can
  # see when the car is needed again and where it's headed.
  def next_booking(after: Time.current)
    bookings.where(status: %w[active awaiting_return], parent_booking_id: nil)
            .where("start_at > ?", after)
            .order(:start_at)
            .first
  end

  def bookable?
    active? && !recharging?
  end

  # ── Fast bruger (regular user) hold ───────────────────────────────
  # The car's fast bruger by display name — the linked member, or the free-text
  # fallback for non-members.
  def regular_driver_name
    regular_user&.name.presence || regular_driver.presence
  end

  # Whether this car is held for its fast bruger against `booker` for the window
  # [start_at, end_at). Held when there's a regular_user, the booker isn't them,
  # that week's hold is still active, and the window overlaps their working hours.
  def held_for?(start_at, end_at, booker)
    return false unless regular_user && start_at && end_at
    return false if booker && booker == regular_user
    week_start = start_at.to_date.beginning_of_week(:monday)
    return false unless regular_hold_active?(week_start)
    overlaps_regular_working_hours?(start_at, end_at)
  end

  # A week's hold runs until the Saturday-12:00 checkpoint before it, and then
  # lapses: from that moment the car is first-come-first-served for everyone.
  # Days the fast bruger has already booked are protected by the overlap check.
  def regular_hold_active?(week_start)
    Time.current < claim_deadline_for(week_start)
  end

  # Saturday noon before the given week — the moment the fast bruger's first
  # claim on it expires.
  def claim_deadline_for(week_start)
    (week_start - 2).in_time_zone.change(hour: 12)
  end

  # A fast bruger's car is held 06:00–18:00 every day by default. Setting working
  # hours on their member page replaces that default, day by day — an explicitly
  # blank day means the car is free all day.
  DEFAULT_HOLD = { "start" => "06:00", "end" => "18:00" }.freeze

  # Does [start_at, end_at) overlap the fast bruger's held hours on any day it spans?
  def overlaps_regular_working_hours?(start_at, end_at)
    custom = regular_user.working_hours?
    (start_at.to_date..end_at.to_date).any? do |day|
      wh = custom ? regular_user.working_hours_for(day.cwday) : DEFAULT_HOLD
      next false unless wh
      sh, sm = wh["start"].split(":").map(&:to_i)
      eh, em = wh["end"].split(":").map(&:to_i)
      wh_start = day.in_time_zone.change(hour: sh, min: sm)
      wh_end   = day.in_time_zone.change(hour: eh, min: em)
      start_at < wh_end && end_at > wh_start
    end
  end

  def start_recharge!(until_time)
    update!(recharge_until: until_time)
  end

  def finish_recharge!
    update!(recharge_until: nil)
  end

  private

  def ensure_qr_token
    self.qr_token ||= self.class.generate_unique_qr_token
  end
end
