require "test_helper"

# Required-check-in flow: a car can't be ended until it's been checked in, and the
# QR page swaps from the check-in form to the end form once the trip has started.
class CheckInFlowTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      c  = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
      c.resource_prices.create!(user_type: "resident", hour_rate: 10, day_rate: 0, km_rate: 2.5, min_charge: 0)
      c.create_resource_stat!(data: { "mileage" => 1000 })
      c
    end
  end

  def booking
    @booking ||= Booking.create!(resource: car, user: user, destination: "Town",
                                 start_at: 1.hour.ago, end_at: 2.hours.from_now, status: "active")
  end

  def user
    @user ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                           name: "Dan", email: "d#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  test "ending a car before check-in is blocked with a prompt to check in first" do
    post reservation_completion_path, params: { token: car.qr_token, booking_id: booking.id, ending_reading: 1100 }

    assert_redirected_to vehicle_scan_path(car.qr_token)
    assert_equal I18n.t("reservations.flash.check_in_first"), flash[:alert]
    assert_equal "active", booking.reload.status
  end

  test "check-in shows a safe-journey screen, and the QR page then shows the end form" do
    post reservation_check_in_path, params: { token: car.qr_token, booking_id: booking.id, starting_reading: 1010 }
    assert_response :success
    assert_match I18n.t("reservations.checked_in.title"), @response.body
    assert_match I18n.t("reservations.checked_in.return_hint"), @response.body
    assert_equal "awaiting_return", booking.reload.status

    get vehicle_scan_path(car.qr_token)
    assert_match I18n.t("reservations.completion.end_button"), @response.body
    assert_no_match(/#{Regexp.escape(I18n.t("reservations.check_in.button"))}/, @response.body)
  end

  test "ending shows a km-confirmation screen before finalising, then finishes on confirm" do
    post reservation_check_in_path, params: { token: car.qr_token, booking_id: booking.id, starting_reading: 1000 }

    # First end submission (no confirmed flag) → confirmation screen, not yet done.
    assert_no_difference -> { Transaction.count } do
      post reservation_completion_path, params: { token: car.qr_token, booking_id: booking.id, ending_reading: 1150 }
    end
    assert_response :success
    assert_match I18n.t("reservations.confirm.you_drove"), @response.body
    assert_match "150 km", @response.body            # 1150 - 1000
    assert_equal "awaiting_return", booking.reload.status, "not finalised until confirmed"

    # Confirm → actually completes.
    post reservation_completion_path, params: { token: car.qr_token, booking_id: booking.id, ending_reading: 1150, confirmed: "1" }
    assert_response :success
    assert_match I18n.t("reservations.completed.title"), @response.body
    assert_equal "returned", booking.reload.status
    assert_equal 1150, booking.end_mileage
  end

  test "an invalid reading is caught before the confirmation screen" do
    post reservation_check_in_path, params: { token: car.qr_token, booking_id: booking.id, starting_reading: 1000 }

    post reservation_completion_path, params: { token: car.qr_token, booking_id: booking.id, ending_reading: 900 }
    assert_redirected_to vehicle_scan_path(car.qr_token)
    assert_equal "awaiting_return", booking.reload.status
  end

  test "a forged booking_id for another car cannot be checked in through this token" do
    other = Resource.create!(name: "Other", status: "active", resource_type: car.resource_type)
    other.create_resource_stat!(data: { "mileage" => 500 })
    foreign = Booking.create!(resource: other, user: user, destination: "X",
                              start_at: 1.hour.ago, end_at: 1.hour.from_now, status: "active")

    post reservation_check_in_path, params: { token: car.qr_token, booking_id: foreign.id, starting_reading: 1010 }

    assert_redirected_to vehicle_scan_path(car.qr_token)
    assert_equal "active", foreign.reload.status
    assert_nil foreign.checked_in_at
  end
end
