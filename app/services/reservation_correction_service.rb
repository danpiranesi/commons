# Corrects an already-completed reservation: the odometer readings, the actual
# return time, or both. Self-service completion has no human check, so this is
# how an admin fixes a bad reading or a trip closed late by the next scan.
#
# The ledger is immutable, so this posts an OFFSETTING transaction for the
# delta rather than editing the original charge, and re-prices through the same
# PricingCalculator the completion used, at the rate frozen when it completed.
#
#   ReservationCorrectionService.call(booking:, ending_reading:, corrected_by:)
#   ReservationCorrectionService.call(booking:, starting_reading:, corrected_by:)
#   ReservationCorrectionService.call(booking:, completed_at:,   corrected_by:)
class ReservationCorrectionService
  Result = Data.define(:success, :booking, :new_amount, :delta, :error) do
    def success? = success
    def failure? = !success
  end

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(booking:, ending_reading: nil, starting_reading: nil, completed_at: nil, corrected_by: nil)
    @booking          = booking
    @ending_reading   = ending_reading.present? ? ending_reading.to_i : nil
    @starting_reading = starting_reading.present? ? starting_reading.to_i : nil
    @completed_at   = completed_at.present? ? completed_at.in_time_zone : nil
    @corrected_by   = corrected_by
  end

  def call
    return failure(:not_completed) unless @booking.status == "returned"
    return failure(:nothing_to_correct) if @ending_reading.nil? && @starting_reading.nil? && @completed_at.nil?

    if @ending_reading || @starting_reading
      return failure(:not_distance_billed) unless @booking.resource.tracks_mileage?
      return failure(:reading_too_low) if effective_end_reading.to_i < start_reading
      # No implausible-delta cap here on purpose: the admin *is* the human check
      # this flow exists to provide, and a correction may legitimately be large.
    end

    if @completed_at
      return failure(:returned_before_start) if @completed_at <= @booking.start_at
    end

    # Billing reads the return time off the booking (Booking#billed_hours), so
    # the corrected time has to be on the object before the trip is re-priced.
    @booking.completed_at = @completed_at if @completed_at

    new_breakdown = recomputed_breakdown
    # Re-apply the member's (or the group's) rate, exactly as completion does.
    new_rate   = rate_for(base_total: new_breakdown.total,
                          km: effective_end_reading.to_i - start_reading)
    new_amount = new_rate.charged
    delta      = new_amount - @booking.total_amount

    ActiveRecord::Base.transaction do
      @booking.update!(
        start_mileage:    (@starting_reading || @booking.start_mileage),
        end_mileage:      effective_end_reading,
        completed_at:     @booking.completed_at,
        total_amount:     new_amount,
        charge_breakdown: ReservationCompletionService.breakdown_hash(new_breakdown),
        # Re-freeze the rate too, so the monthly sheet's base and charged
        # columns keep reconciling.
        billing_rate:     new_rate.for_storage
      )
      # Only trips collected through a personal ledger have a transaction to
      # offset; invoiced people and groups have none.
      post_offsetting_transaction(delta) if @booking.collected_via_ledger?
      update_resource_odometer_if_latest if @ending_reading
    end

    ReceiptMailer.correction(@booking).deliver_later if @booking.user&.wants_receipt?
    Result.new(success: true, booking: @booking, new_amount: new_amount, delta: delta, error: nil)
  rescue ActiveRecord::RecordInvalid
    failure(:persist_failed)
  end

  private

  # The rate to charge the corrected trip at: the one frozen when it completed,
  # falling back to the member's category for trips finished before rates were
  # stored. Looking the category up afresh would re-price an old trip at whatever
  # the member is on today.
  def rate_for(base_total:, km:)
    frozen = @booking.billing_rate_struct
    return @booking.billing_rate_for(base_total: base_total, km: km) if frozen.nil?

    frozen.reapply(base_total: base_total, km: km)
  end

  # A trip "started" at the reading it was returned with bills 0 km. The start
  # is then as wrong as any end reading, and corrected the same way.
  def start_reading
    (@starting_reading || @booking.start_mileage).to_i
  end

  # The reading the corrected trip ends at: the new one if given, else whatever
  # was recorded, so correcting only the time keeps the distance as it was.
  def effective_end_reading
    @ending_reading || @booking.end_mileage
  end

  def recomputed_breakdown
    PricingCalculator.new(
      @booking, start_odometer: start_reading, ending_reading: effective_end_reading
    ).breakdown
  end

  # Net ledger for this booking must become -new_amount. The original -old_amount
  # is already posted, so add -(new-old) = -delta. Positive delta → extra charge;
  # negative delta → refund. Nothing to do when the amount is unchanged.
  def post_offsetting_transaction(delta)
    return if delta.zero?

    account = @booking.user.account || @booking.user.create_account!
    account.transactions.create!(
      user:        @booking.user,
      amount:      -delta,
      description: correction_description,
      booking:     @booking,
      created_by:  @corrected_by
    )
  end

  # Keep the resource's running odometer truthful only if this was its most recent
  # completion; correcting an older booking must not rewind a newer reading.
  def update_resource_odometer_if_latest
    resource = @booking.resource
    latest   = resource.bookings.where(status: "returned").maximum(:completed_at)
    return if latest.nil? || @booking.completed_at.nil? || @booking.completed_at < latest

    resource.current_odometer = @ending_reading
    resource.resource_stat.save!
  end

  def correction_description
    "#{@booking.resource.display_name} — #{I18n.t('receipts.correction.ledger', date: @booking.start_at.to_date)}"
  end

  def failure(error)
    Result.new(success: false, booking: @booking, new_amount: nil, delta: nil, error: error)
  end
end
