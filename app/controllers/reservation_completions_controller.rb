# Shared POST target for ending a reservation from the QR page, the kiosk, and the
# active-booking panel. The token proves scope, so this path is public; the booking
# is always re-derived through resource.bookings, so a forged booking_id for another
# car resolves to 404, not someone else's reservation.
class ReservationCompletionsController < ApplicationController
  skip_before_action :authenticate_user!, only: :create
  # The QR token is the credential; scoping through resource.bookings stands in
  # for CSRF protection on this public endpoint.
  skip_forgery_protection only: :create
  layout "minimal"

  def create
    resource = Resource.find_by!(qr_token: params[:token])
    # Not status-filtered on purpose: a re-submit of an already-returned booking
    # still resolves here and the service returns :already_completed idempotently.
    booking  = resource.bookings.find(params[:booking_id])

    # Cars must be checked in (start odometer recorded) before they can be ended.
    # The auto-close path bypasses this by calling the service directly, and so
    # does a driver who never checked in and says so on the check-in form: their
    # trip is measured from the car's last recorded reading.
    if booking.needs_check_in? && params[:end_without_check_in].blank?
      return redirect_to return_path(resource), alert: t("reservations.flash.check_in_first")
    end

    # For mileage-tracked cars (when the type's rules require it), show a "you
    # drove X km — confirm?" screen before finalising. The confirmation form
    # re-posts here with confirmed=1.
    if booking.resource.tracks_mileage? && booking.rules.require_confirmation? && params[:confirmed].blank?
      preview = ReservationCompletionService.preview(booking: booking, ending_reading: params[:ending_reading])
      if preview.success?
        @resource, @booking, @preview = resource, booking, preview
        @return_to = safe_internal_path(params[:return_to])
        return render :confirm
      else
        return redirect_to return_path(resource), alert: error_message(preview)
      end
    end

    result = ReservationCompletionService.call(
      booking:         booking,
      ending_reading:  params[:ending_reading],
      completed_by:    current_user
    )

    if result.success?
      # The QR-at-the-car flow gets a "trip ended" page; the panel and kiosk
      # (which pass return_to) go back with a flash.
      if params[:return_to].present?
        redirect_to return_path(resource), notice: success_message(result)
      else
        @resource, @booking, @result = resource, booking, result
        render :completed
      end
    else
      redirect_to return_path(resource), alert: error_message(result)
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to vehicle_scan_path(params[:token]), alert: t("reservations.flash.not_found")
  end

  private

  # QR/kiosk callers land back on the scan page; the authenticated panel passes
  # return_to so it comes back to the dashboard instead.
  def return_path(resource)
    safe_internal_path(params[:return_to]) || vehicle_scan_path(resource.qr_token)
  end

  def success_message(result)
    if result.amount.to_f.zero?
      t("reservations.flash.completed_free")
    else
      t("reservations.flash.completed", amount: helpers.number_with_delimiter(result.amount))
    end
  end

  def error_message(result)
    case result.error
    when :already_completed
      t("reservations.flash.already_completed")
    when :missing_reading, :missing_start_odometer
      t("reservations.flash.missing_reading")
    when :reading_too_low
      t("reservations.flash.reading_too_low", km: helpers.number_with_delimiter(result.meta[:current]))
    when :reading_implausible
      t("reservations.flash.reading_implausible", max: helpers.number_with_delimiter(result.meta[:max]))
    else
      t("reservations.flash.error")
    end
  end
end
