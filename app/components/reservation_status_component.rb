# Shared status display for a resource's current reservation, used by the QR
# landing page, the active-booking panel and the kiosk.
#
#   render(ReservationStatusComponent.new(resource:, booking:, recent_booking:,
#                                         upcoming_booking:, context: :qr)) do |c|
#     c.with_actions { ... end/extend forms ... }
#   end
class ReservationStatusComponent < ViewComponent::Base
  renders_one :actions

  # booking:          the reservation that is out now, or overdue and unclosed
  # recent_booking:   the most recently returned one, for the "already ended" note
  # upcoming_booking: the next one due, so an early arrival is never told they
  #                   have no booking
  # context:          :qr | :panel | :kiosk — for copy/styling differences only
  def initialize(resource:, booking: nil, recent_booking: nil, upcoming_booking: nil, context: :qr)
    @resource         = resource
    @booking          = booking
    @recent_booking   = recent_booking
    @upcoming_booking = upcoming_booking
    @context          = context
  end

  def state
    return :active   if @booking
    return :ended    if @recent_booking
    return :upcoming if @upcoming_booking
    :none
  end

  def active?
    state == :active
  end

  # A trip that is past its return time and still open.
  def overdue?
    @booking&.overdue?
  end

  # When the driver may start the trip they can see but not yet act on.
  def checkout_opens_at
    return nil unless @upcoming_booking
    @upcoming_booking.start_at - BookingRules.for(@resource.resource_type).checkout_buffer_minutes.minutes
  end
end
