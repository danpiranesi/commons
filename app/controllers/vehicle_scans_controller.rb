# Public QR landing page: GET /v/:token. No auth, no session — the token itself is
# the credential. Every query is scoped off the resource the token
# resolves to, never a raw id from the client.
class VehicleScansController < ApplicationController
  skip_before_action :authenticate_user!, only: :show
  layout "minimal"

  # How far ahead a not-yet-started reservation is surfaced. Long enough that
  # somebody arriving early is told when they can start rather than that they
  # have no booking; short enough that a drive-by scan of an idle car does not
  # announce who has it next week.
  UPCOMING_HORIZON = 12.hours

  def show
    @resource = Resource.find_by!(qr_token: params[:token])
    @booking  = live_booking_for(@resource)

    # Only when nothing is out: the "already ended" message for a genuinely
    # recent return, else the next trip due, so the page is never a dead end.
    if @booking.nil?
      @recent_booking   = recent_return_for(@resource)
      @upcoming_booking = upcoming_booking_for(@resource) if @recent_booking.nil?
    end
  rescue ActiveRecord::RecordNotFound
    render :not_found, status: :not_found
  end

  private

  # Every reservation on this vehicle that has not been ended, oldest first.
  # Cancelled and returned trips are gone; what is left is what somebody standing
  # at the car might need to act on.
  def open_bookings_for(resource)
    resource.bookings
            .where(status: ReservationCompletionService::COMPLETABLE_STATUSES, completed_at: nil)
            .includes(:user, resource: :resource_type)
            .order(:start_at)
            .to_a
  end

  # The reservation this scan is about, if the car is out or should be.
  #
  # Order matters, and it is deliberately "who has actually started" first:
  #
  #   1. a trip that has begun and is not yet past its return time
  #   2. a trip that has begun, is past its return time, and was never ended
  #   3. only if the car is idle, a trip due to start within the check-out buffer
  #
  # A driver who is still out always wins over one arriving early, so a late
  # return can always be closed. Step 2 deliberately applies no buffer.
  def live_booking_for(resource)
    now     = Time.current
    rules   = BookingRules.for(resource.resource_type)
    started, upcoming = open_bookings_for(resource).partition { |b| b.start_at <= now }

    current = started.select { |b| now <= b.end_at + rules.return_buffer_minutes.minutes }
                     .max_by(&:start_at)
    return current if current

    overdue = started.max_by(&:end_at)
    return overdue if overdue

    upcoming.select { |b| b.start_at - rules.checkout_buffer_minutes.minutes <= now }
            .min_by(&:start_at)
  end

  # The next reservation due on an idle car. Shown so an early arrival sees their
  # booking and the time they can start it, instead of "no active reservation".
  def upcoming_booking_for(resource)
    now = Time.current
    open_bookings_for(resource)
      .select { |b| b.start_at > now && b.start_at <= now + UPCOMING_HORIZON }
      .min_by(&:start_at)
  end

  def recent_return_for(resource)
    resource.bookings
            .where(status: "returned")
            .where("completed_at >= ?", 1.hour.ago)
            .order(completed_at: :desc)
            .first
  end
end
