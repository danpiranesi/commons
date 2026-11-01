# Closes bookings for resources that carry no odometer (bikes, trailers, boxes)
# once their booked end time has passed. Those resources are never checked in or
# out at the vehicle, so nothing would otherwise end the reservation — it would
# sit open and keep the resource looking busy.
#
# Mileage-tracked resources are deliberately left alone: their trip is closed by
# the driver at the car (or reconciled by the next driver's check-in), because
# the closing odometer has to come from a person.
class AutoCompleteBookingsJob < ApplicationJob
  queue_as :default

  def perform
    due_bookings.find_each do |booking|
      ReservationCompletionService.call(booking: booking, completed_by: nil)
    end
  end

  private

  def due_bookings
    Booking.joins(resource: :resource_type)
           .where(status: ReservationCompletionService::COMPLETABLE_STATUSES)
           .where(parent_booking_id: nil)
           .where("bookings.end_at <= ?", Time.current)
           .where.not(resource_types: { billing_type: "per_day_and_km" })
  end
end
