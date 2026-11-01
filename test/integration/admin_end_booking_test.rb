require "test_helper"

# Admins can end an active booking that was never returned via QR, entering the
# ending mileage from the booking detail view. Routes through the same completion
# service as a normal return.
class AdminEndBookingTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  def member
    @member ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                             name: "Mia", email: "m#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      c = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
      c.resource_prices.create!(user_type: "resident", hour_rate: 10, day_rate: 0, km_rate: 2.5, min_charge: 0)
      c.create_resource_stat!(data: { "mileage" => 1000 })
      c
    end
  end

  def active_booking
    Booking.create!(resource: car, user: member, destination: "Town",
                    start_at: 3.hours.ago, end_at: 1.hour.ago, status: "active", start_mileage: 1000)
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "the end-booking card shows on an active booking for admins" do
    b = active_booking
    sign_in(admin)
    get booking_path(b)
    assert_response :success
    assert_match I18n.t("bookings.show.end_card_title"), @response.body
    assert_match I18n.t("bookings.show.end_mileage_label"), @response.body
  end

  test "the end-booking card is hidden from non-admins" do
    b = active_booking
    sign_in(member)
    get booking_path(b)
    assert_no_match I18n.t("bookings.show.end_card_title"), @response.body
  end

  test "an admin ends the booking with an entered reading and it is charged" do
    b = active_booking
    sign_in(admin)

    patch complete_booking_path(b), params: { ending_reading: 1150 }
    b.reload
    assert_equal "returned", b.status
    assert_equal 1150, b.end_mileage
    assert b.total_amount.to_f > 0, "the trip was charged"
    assert_equal 1150, car.reload.current_odometer, "odometer advanced"
  end

  test "a non-admin cannot force-end a booking" do
    b = active_booking
    sign_in(member)
    patch complete_booking_path(b), params: { ending_reading: 1150 }
    assert_equal "active", b.reload.status
  end

  test "a too-low reading is rejected with a clear message" do
    b = active_booking
    sign_in(admin)
    patch complete_booking_path(b), params: { ending_reading: 900 }
    assert_equal "active", b.reload.status
    follow_redirect!
    km = ActionController::Base.helpers.number_with_delimiter(1000)
    assert_match I18n.t("reservations.flash.reading_too_low", km: km), @response.body
  end
end
