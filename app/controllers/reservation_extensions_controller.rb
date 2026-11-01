# Shared POST target for extending an active reservation from the QR page or panel.
# Same scoping model as completion. No billing on extend — the existing
# no_overlapping_bookings validation on Booking blocks a clash with the next
# reservation, so we just try to move end_at and surface the validation error.
class ReservationExtensionsController < ApplicationController
  skip_before_action :authenticate_user!, only: :create
  skip_forgery_protection only: :create
  layout "minimal"

  def create
    resource = Resource.find_by!(qr_token: params[:token])
    booking  = resource.bookings.where(status: %w[active awaiting_return]).find(params[:booking_id])

    # Extension can be disabled per resource type on the Rules page.
    unless BookingRules.for(resource.resource_type).allow_extension?
      return redirect_to return_path(resource), alert: t("reservations.flash.extend_disabled")
    end

    # Parse the naive datetime-local value in the app's zone (Europe/Copenhagen),
    # matching how bookings are created via the wizard's Time.zone builders.
    new_end  = Time.zone.parse(params[:new_end].to_s) rescue nil

    if new_end.nil? || new_end <= booking.start_at
      return redirect_to return_path(resource), alert: t("reservations.flash.extend_failed")
    end

    # Shortening belongs in the edit form, where the shorten penalty is applied.
    # Compared to the minute, since that is all the datetime-local field carries.
    if new_end < booking.end_at.change(sec: 0, usec: 0)
      return redirect_to return_path(resource), alert: t("reservations.flash.extend_not_shorter")
    end

    # Refuse up front with the latest possible end time, rather than bouncing off
    # the overlap validation.
    ceiling = booking.max_extension_end
    if ceiling && new_end > ceiling
      return redirect_to return_path(resource),
                         alert: t("reservations.flash.extend_conflict", time: ceiling.strftime("%-d/%-m %H:%M"))
    end

    if booking.with_resource_lock { booking.update(end_at: new_end) }
      redirect_to return_path(resource), notice: t("reservations.flash.extended")
    else
      redirect_to return_path(resource),
                  alert: booking.errors.full_messages.to_sentence.presence || t("reservations.flash.extend_failed")
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
end
