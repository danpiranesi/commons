# On-site kiosk end-reservation flow. Public — the physical device is the access
# control. Look up your unfinished reservations by the last 4 digits of your
# phone, then end one through the same completion form/service as the QR page.
class KioskController < ApplicationController
  skip_before_action :authenticate_user!, only: :show
  layout "minimal"

  def show
    @digits = params[:phone].to_s.gsub(/\D/, "")
    return unless @digits.length == 4

    @searched = true
    @bookings = unfinished_bookings_for_last4(@digits)
  end

  private

  # Active/awaiting-return, already-started, top-level reservations belonging to a
  # user whose phone ends in these 4 digits. Phone is normalized to digits so
  # stored spacing/formatting doesn't matter.
  def unfinished_bookings_for_last4(last4)
    user_ids = User.where.not(phone: [nil, ""])
                   .select { |u| u.phone.gsub(/\D/, "").end_with?(last4) }
                   .map(&:id)
    return Booking.none if user_ids.empty?

    Booking.where(user_id: user_ids, status: %w[active awaiting_return], parent_booking_id: nil)
           .where("start_at <= ?", Time.current)
           .includes(:resource, :user)
           .order(:start_at)
  end
end
