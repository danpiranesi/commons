require "test_helper"

# End-to-end coverage for the QR entry point: scan → see status → end
# reservation → idempotent re-scan, plus token scoping.
class VehicleScanFlowTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def make_user(name: "Alice Resident")
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                 name: name, email: "u#{SecureRandom.hex(6)}@example.com", user_type: "resident")
  end

  def make_car(start_odometer: 1000)
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 99)
    car = Resource.create!(name: "Car-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    car.resource_prices.create!(user_type: "resident", hour_rate: 10, day_rate: 0, km_rate: 2.5, min_charge: 0)
    car.create_resource_stat!(data: { "mileage" => start_odometer })
    car
  end

  def make_booking(car:, user:, status: "active")
    Booking.create!(resource: car, user: user, start_at: 2.hours.ago, end_at: Time.current,
                    status: status, destination: "Town")
  end

  test "scanning a not-yet-started car reservation shows who it's for and the check-in action" do
    car = make_car
    booking = make_booking(car: car, user: make_user(name: "Alice Resident"))

    get vehicle_scan_path(car.qr_token)

    assert_response :success
    assert_select "h2", text: car.display_name
    assert_match "Alice Resident", @response.body
    # A car must be checked in before it can be ended, so the first action is check-in.
    assert_match I18n.t("reservations.check_in.button"), @response.body
    # The odometer field is pre-filled with the last stored reading, just editable.
    assert_select "input[name=?][value=?]", "starting_reading", "1000"
  end

  test "checking in then ending via the QR post marks returned, charges the account, and re-scan is idempotent" do
    car = make_car(start_odometer: 1000)
    user = make_user
    booking = make_booking(car: car, user: user)

    # Start the trip (records the starting odometer, flips to awaiting_return).
    post reservation_check_in_path, params: { token: car.qr_token, booking_id: booking.id, starting_reading: 1000 }
    assert_equal "awaiting_return", booking.reload.status

    assert_difference -> { Transaction.count }, 1 do
      post reservation_completion_path, params: { token: car.qr_token, booking_id: booking.id, ending_reading: 1150, confirmed: "1" }
    end
    assert_response :success
    assert_match I18n.t("reservations.completed.title"), @response.body

    booking.reload
    assert_equal "returned", booking.status
    assert_equal 1150, booking.end_mileage
    assert_not_nil booking.total_amount
    assert_equal 1150, car.reload.current_odometer

    # Re-scanning shows the "already ended" state, not an error.
    get vehicle_scan_path(car.qr_token)
    assert_response :success
    assert_match I18n.t("reservations.status.already_ended", name: booking.display_name), @response.body
  end

  test "a low odometer reading is rejected with a flash and no charge" do
    car = make_car(start_odometer: 1000)
    booking = make_booking(car: car, user: make_user)

    assert_no_difference -> { Transaction.count } do
      post reservation_completion_path, params: { token: car.qr_token, booking_id: booking.id, ending_reading: 900 }
    end
    assert_redirected_to vehicle_scan_path(car.qr_token)
    assert_equal "active", booking.reload.status
  end

  test "a booking_id from another car cannot be completed through this car's token" do
    car_a = make_car
    car_b = make_car
    booking_b = make_booking(car: car_b, user: make_user)

    # Forged: car_a's token + car_b's booking, looked up through car_a's bookings.
    post reservation_completion_path, params: { token: car_a.qr_token, booking_id: booking_b.id, ending_reading: 1150 }

    assert_redirected_to vehicle_scan_path(car_a.qr_token)
    assert_equal "active", booking_b.reload.status
  end

  test "an idle vehicle shows a neutral message and leaks no member name" do
    car = make_car
    make_booking(car: car, user: make_user(name: "Bob Resident"), status: "returned")

    get vehicle_scan_path(car.qr_token)

    assert_response :success
    assert_match I18n.t("reservations.status.no_active"), @response.body
    assert_no_match "Bob Resident", @response.body
  end

  test "an unknown token renders a neutral not-found page" do
    get vehicle_scan_path("nonexistent-token")
    assert_response :not_found
    assert_match I18n.t("vehicle_scans.not_found_title"), @response.body
  end
end
