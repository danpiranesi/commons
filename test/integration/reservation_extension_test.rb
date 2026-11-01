require "test_helper"

# The QR "Forlæng" form. It moves a booking's end time later; it is not a way to
# shorten one, because shortening carries a penalty that only the edit form
# applies.
class ReservationExtensionTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    freeze_time
    @user = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Fører",
                         email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident")
    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    @car = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    @car.create_resource_stat!(data: { "mileage" => 10_000 })
    @booking = Booking.create!(resource: @car, user: @user, destination: "Town",
                               status: "awaiting_return", start_at: 1.hour.ago,
                               end_at: 5.hours.from_now, checked_in_at: 1.hour.ago,
                               start_mileage: 10_000)
  end

  teardown { travel_back }

  def extend_to(time)
    post reservation_extension_path, params: {
      token: @car.qr_token, booking_id: @booking.id,
      new_end: time.strftime("%Y-%m-%dT%H:%M")
    }
  end

  test "an extension moves the end time later" do
    extend_to(7.hours.from_now)
    assert_equal 7.hours.from_now.change(sec: 0), @booking.reload.end_at.change(sec: 0)
  end

  test "an extension cannot be used to shorten a booking" do
    original = @booking.end_at
    extend_to(2.hours.from_now)
    assert_equal original, @booking.reload.end_at,
                 "shortening here would skip the penalty the edit form applies"
    assert_equal I18n.t("reservations.flash.extend_not_shorter"), flash[:alert]
  end

  test "re-submitting the same end time is accepted rather than rejected as a shortening" do
    extend_to(@booking.end_at)
    assert_nil flash[:alert]
  end
end
