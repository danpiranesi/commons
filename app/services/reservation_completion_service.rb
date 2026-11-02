# The one shared path for ending a reservation, whatever the entry point
# (QR scan, kiosk, active-booking panel, admin manual booking). Every caller
# routes through here so the price calc, odometer math, transaction safety and
# receipt can't drift between them.
#
# Usage:
#   result = ReservationCompletionService.call(
#     booking:,
#     ending_reading:,      # required for per_day_and_km resources, ignored otherwise
#     completed_by:,        # admin/kiosk operator, if any (else nil = the renter)
#     allow_high_delta:     # true to accept an odometer delta over the sanity cap
#   )
#   result.success?  # => true / false
#   result.error     # => symbol on failure (:already_completed, :reading_too_low, …)
#   result.amount    # => charged amount (Decimal) on success
#   result.breakdown # => PricingCalculator::Breakdown on success
#   result.meta      # => extra context (e.g. { delta:, max: } for :reading_implausible)
class ReservationCompletionService
  # A single reservation shouldn't plausibly cover more than this many km. Exceeding
  # it usually means a fat-fingered extra digit (450 entered as 4500). Flag, don't
  # silently accept — a wrong charge and receipt would otherwise go out.
  MAX_KM_PER_RESERVATION = 2_000

  COMPLETABLE_STATUSES = %w[active awaiting_return].freeze

  Result = Data.define(:success, :booking, :breakdown, :amount, :error, :meta) do
    def success? = success
    def failure? = !success
  end

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def self.preview(**kwargs)
    new(**kwargs).preview
  end

  # Serialize a Breakdown to the jsonb we store on bookings (strings preserve
  # decimal precision through jsonb). Shared with ReservationCorrectionService.
  def self.breakdown_hash(breakdown)
    {
      "time_cost"      => breakdown.time_cost.to_s,
      "km_cost"        => breakdown.km_cost.to_s,
      "toll_cost"      => breakdown.toll_cost.to_s,
      "accessory_cost" => breakdown.accessory_cost.to_s
    }
  end

  def initialize(booking:, ending_reading: nil, completed_by: nil, allow_high_delta: false)
    @booking          = booking
    @ending_reading   = ending_reading.present? ? ending_reading.to_i : nil
    @completed_by     = completed_by
    @allow_high_delta = allow_high_delta
  end

  def call
    # Idempotent: a second scan after the booking already ended is not an error.
    return failure(:already_completed) unless completable?

    if requires_odometer?
      odometer_error = validate_odometer
      return odometer_error if odometer_error
    end

    amount = nil

    # Hold a row lock across the check-and-charge, so a double-tapped confirm or
    # a retried request cannot charge the same trip twice.
    ActiveRecord::Base.transaction do
      # Re-read the status under the lock, so a completion that landed while we
      # were pricing is seen. Read as a bare column rather than reloading the
      # record: the caller holds this booking and renders from it afterwards.
      next unless COMPLETABLE_STATUSES.include?(locked_status)

      # Set the completion time in memory before pricing so an early return is
      # prorated (Booking#billed_hours reads completed_at). Persisted below.
      @booking.completed_at = completion_time

      @breakdown = PricingCalculator.new(
        @booking, start_odometer: start_odometer, ending_reading: @ending_reading
      ).breakdown

      # Apply the member's (or the group's) rate to the base charge. Uncategorised
      # trips resolve to a x1 "normal" rate, so this changes nothing for them.
      @rate  = @booking.billing_rate_for(base_total: @breakdown.total, km: charged_km)
      amount = @rate.charged

      persist_completion!(amount)
      # Only bank-transfer categories (members, and the uncategorised default)
      # hit a personal ledger. Invoiced and internal categories — HP people and
      # every group — are billed through the monthly sheet, so a group's state-rate
      # charge never lands on whoever happened to drive.
      deduct_account!(amount) if @booking.collected_via_ledger?
    end

    return failure(:already_completed) if amount.nil?

    # Outside the transaction: SMTP/queue hiccups must never roll back billing.
    enqueue_receipt

    success(@breakdown, amount)
  rescue ActiveRecord::RecordInvalid => e
    failure(:persist_failed, message: e.message)
  end

  # Distance for a per-km (state) rate. Zero for non-mileage resources.
  def charged_km
    requires_odometer? ? (@ending_reading.to_i - start_odometer.to_i) : 0
  end

  # Validate the reading and compute km + amount WITHOUT persisting — powers the
  # "you drove X km, confirm?" screen shown before an end is finalised.
  def preview
    return failure(:already_completed) unless completable?

    if requires_odometer?
      odometer_error = validate_odometer
      return odometer_error if odometer_error
    end

    @booking.completed_at = completion_time # so proration matches the real charge
    breakdown = PricingCalculator.new(
      @booking, start_odometer: start_odometer, ending_reading: @ending_reading
    ).breakdown
    km = requires_odometer? ? (@ending_reading - start_odometer) : 0

    # The confirm screen shows what will actually be charged, rate applied.
    rate = @booking.billing_rate_for(base_total: breakdown.total, km: km)

    Result.new(success: true, booking: @booking, breakdown: breakdown, amount: rate.charged,
               error: nil, meta: { km: km, start_odometer: start_odometer,
                                   ending_reading: @ending_reading, rate: rate })
  end

  private

  def resource
    @booking.resource
  end

  def billing_type
    resource.resource_type.billing_type
  end

  def requires_odometer?
    billing_type == "per_day_and_km"
  end

  def completable?
    COMPLETABLE_STATUSES.include?(@booking.status)
  end

  # This booking's status straight from the database, with the row locked for the
  # rest of the transaction. Anyone else trying to complete the same trip waits
  # here and then finds it already returned.
  def locked_status
    Booking.lock.where(id: @booking.id).pick(:status)
  end

  def completion_time
    @completion_time ||= Time.current
  end

  # When the driver checked in, their entered start reading is authoritative for
  # this trip. Otherwise fall back to the resource's running odometer, then the
  # booking's seeded start_mileage (the path an auto-closed booking takes).
  def start_odometer
    @start_odometer ||= if @booking.checked_in? && @booking.start_mileage
                          @booking.start_mileage
    else
                          resource.current_odometer || @booking.start_mileage
    end
  end

  def validate_odometer
    return failure(:missing_reading) if @ending_reading.nil?
    return failure(:missing_start_odometer) if start_odometer.nil?

    if @ending_reading < start_odometer
      return failure(:reading_too_low, meta: { current: start_odometer, entered: @ending_reading })
    end

    delta = @ending_reading - start_odometer
    max_km = BookingRules.for(resource.resource_type).max_km_per_trip
    if delta > max_km && !@allow_high_delta
      return failure(:reading_implausible, meta: { delta: delta, max: max_km })
    end

    nil
  end

  def persist_completion!(amount)
    if requires_odometer?
      @booking.start_mileage = start_odometer
      @booking.end_mileage   = @ending_reading
      resource.current_odometer = @ending_reading
      resource.resource_stat.save!
    end

    @booking.update!(
      status: "returned",
      total_amount: amount,
      charge_breakdown: self.class.breakdown_hash(@breakdown),
      billing_rate: @rate&.for_storage,
      completed_at: completion_time,
      billing_month: completion_time.strftime("%Y%m")
    )

    # Accessories were billed into this booking's total; close their shadow-bookings
    # so their resource frees up and they never bill again on their own.
    @booking.accessory_bookings.where(status: COMPLETABLE_STATUSES).find_each do |shadow|
      shadow.update!(status: "returned", completed_at: Time.current)
    end
  end

  def deduct_account!(amount)
    return if amount.nil? || amount.zero?

    account = @booking.user.account || @booking.user.create_account!
    account.transactions.create!(
      user:        @booking.user,
      amount:      -amount, # negative = deduction from the internal ledger
      description: receipt_description(amount),
      booking:     @booking,
      created_by:  @completed_by
    )
  end

  def receipt_description(amount)
    # billed_hours (not the booked hours) so the ledger/receipt text matches what
    # was actually charged after an early-return proration.
    "#{resource.display_name} — #{@booking.start_at.to_date} (#{@booking.billed_hours}t)"
  end

  def enqueue_receipt
    return unless @booking.user&.wants_receipt?

    ReceiptMailer.completion(@booking).deliver_later
  end

  def success(breakdown, amount)
    Result.new(success: true, booking: @booking, breakdown: breakdown, amount: amount, error: nil, meta: {})
  end

  def failure(error, meta: {}, message: nil)
    Result.new(success: false, booking: @booking, breakdown: nil, amount: nil, error: error, meta: meta.merge(message ? { message: message } : {}))
  end
end
