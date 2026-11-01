# Start-of-trip check-in: a driver scans the QR when getting into a
# car and enters the real starting odometer. This records the authoritative start
# reading, reconciles the resource's running odometer to reality, and — if the
# previous driver forgot to end their booking — auto-closes it at this reading so
# the new trip is measured correctly regardless of anyone else's mistake.
#
#   ReservationCheckInService.call(booking:, starting_reading:, checked_in_by:)
class ReservationCheckInService
  Result = Data.define(:success, :booking, :error, :meta) do
    def success? = success
    def failure? = !success
  end

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(booking:, starting_reading:, checked_in_by: nil)
    @booking          = booking
    @starting_reading = starting_reading.present? ? starting_reading.to_i : nil
    @checked_in_by    = checked_in_by
  end

  def call
    return failure(:not_applicable) unless resource.tracks_mileage?
    return failure(:already_checked_in) unless @booking.status == "active"
    # Past its end, a trip can only be ended. Starting it now would record the
    # reading at return as the start, and the trip would bill 0 km.
    return failure(:trip_over) if Time.current > @booking.end_at
    return failure(:missing_reading) if @starting_reading.nil?

    # The odometer can't run backwards. A lower reading means a bad prior entry
    # (or a fat-finger now) — flag rather than silently accept.
    current = resource.current_odometer
    if current && @starting_reading < current
      return failure(:reading_too_low, meta: { current: current, entered: @starting_reading })
    end

    ActiveRecord::Base.transaction do
      auto_close_forgotten_bookings!
      @booking.update!(
        start_mileage: @starting_reading,
        checked_in_at: Time.current,
        status:        "awaiting_return"
      )
      resource.current_odometer = @starting_reading
      resource.resource_stat.save!
    end

    Result.new(success: true, booking: @booking, error: nil, meta: {})
  rescue ActiveRecord::RecordInvalid => e
    failure(:persist_failed, meta: { message: e.message })
  end

  private

  def resource
    @booking.resource
  end

  # A previous, still-open reservation on this car means the last driver never
  # ended their trip. Close it at this reading (charging them for the distance up
  # to now). Only earlier bookings whose end_at has passed — so a driver checking
  # out early, within the buffer, never closes the trip of someone still out.
  def auto_close_forgotten_bookings!
    resource.bookings
            .where(status: ReservationCompletionService::COMPLETABLE_STATUSES)
            .where(parent_booking_id: nil)
            .where.not(id: @booking.id)
            .where("start_at <= ?", @booking.start_at)
            .where("end_at <= ?", Time.current)
            .find_each do |forgotten|
      ReservationCompletionService.call(
        booking:          forgotten,
        ending_reading:   @starting_reading,
        completed_by:     @checked_in_by,
        allow_high_delta: true # reconciliation may legitimately be large
      )
    end
  end

  def failure(error, meta: {})
    Result.new(success: false, booking: @booking, error: error, meta: meta)
  end
end
