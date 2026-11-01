# Start-of-trip check-in POST target, shared by the QR page, kiosk and panel.
# Same token-scoped, public model as the completion controller: the qr_token is
# the credential and the booking is re-derived through resource.bookings.
class ReservationCheckInsController < ApplicationController
  skip_before_action :authenticate_user!, only: :create
  skip_forgery_protection only: :create
  layout "minimal"

  def create
    resource = Resource.find_by!(qr_token: params[:token])
    booking  = resource.bookings.find(params[:booking_id])

    result = ReservationCheckInService.call(
      booking:          booking,
      starting_reading: params[:starting_reading],
      checked_in_by:    current_user
    )

    if result.success?
      # QR-at-the-car flow gets a friendly "safe journey" send-off; the panel and
      # kiosk (which pass return_to) go back where they came from with a flash.
      if params[:return_to].present?
        redirect_to return_path(resource), notice: t("reservations.flash.checked_in")
      else
        @resource, @booking = resource, booking
        render :checked_in
      end
    else
      redirect_to return_path(resource), alert: error_message(result)
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to vehicle_scan_path(params[:token]), alert: t("reservations.flash.not_found")
  end

  private

  def return_path(resource)
    safe_internal_path(params[:return_to]) || vehicle_scan_path(resource.qr_token)
  end

  def error_message(result)
    case result.error
    when :reading_too_low
      t("reservations.flash.checkin_too_low", km: helpers.number_with_delimiter(result.meta[:current]))
    when :missing_reading
      t("reservations.flash.checkin_missing")
    when :already_checked_in
      t("reservations.flash.already_checked_in")
    when :trip_over
      t("reservations.flash.check_in_trip_over")
    else
      t("reservations.flash.error")
    end
  end
end
