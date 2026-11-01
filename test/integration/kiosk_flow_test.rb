require "test_helper"

# The on-site kiosk: a public last-4-of-phone lookup surfaces a member's
# unfinished reservations and ends one through the shared completion service.
# Logging out in kiosk mode stays local and returns to the schedule.
class KioskFlowTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def make_user(phone:)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                 name: "Kiosk User", email: "k#{SecureRandom.hex(5)}@example.com",
                 user_type: "resident", phone: phone)
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      c  = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
      c.resource_prices.create!(user_type: "resident", hour_rate: 10, day_rate: 0, km_rate: 2.5, min_charge: 0)
      c.create_resource_stat!(data: { "mileage" => 1000 })
      c
    end
  end

  # A returning driver already checked in at the car when they left, so the kiosk
  # end-flow sees an awaiting_return (checked-in) booking.
  def active_booking(user)
    Booking.create!(resource: car, user: user, destination: "Town",
                    start_at: 2.hours.ago, end_at: 2.hours.from_now, status: "awaiting_return",
                    start_mileage: 1000, checked_in_at: 1.hour.ago)
  end

  test "kiosk is public and prompts for the last 4 digits" do
    get kiosk_path
    assert_response :success
    assert_match I18n.t("kiosk.phone_label"), @response.body
  end

  test "matching last-4 (ignoring formatting) surfaces the unfinished booking with an end form" do
    user = make_user(phone: "+45 12 34 84 67") # last 4 = 8467
    active_booking(user)

    get kiosk_path(phone: "8467")

    assert_response :success
    assert_match "Kiosk User", @response.body
    assert_select "form[action=?]", reservation_completion_path
  end

  test "ending through the kiosk marks the booking returned and returns to the kiosk" do
    user = make_user(phone: "0000 8467")
    booking = active_booking(user)

    post reservation_completion_path, params: {
      token: car.qr_token, booking_id: booking.id, ending_reading: 1080, return_to: kiosk_path, confirmed: "1"
    }

    assert_redirected_to kiosk_path
    assert_equal "returned", booking.reload.status
  end

  test "no match shows an empty state, not an error" do
    make_user(phone: "111 2222") # last 4 = 2222, won't match
    get kiosk_path(phone: "8467")
    assert_response :success
    assert_match I18n.t("kiosk.none_title"), @response.body
  end

  test "kiosk-mode logout is local and returns the wall to the schedule" do
    # Mark this browser as a kiosk device, then sign in and log out.
    get schedule_path(kiosk: "1")
    user = make_user(phone: "9999")
    get "/test/sign_in/#{user.id}"

    delete logout_path
    assert_redirected_to schedule_path
  end

  test "kiosk still finds a booking that is past its return time" do
    user = make_user(phone: "2612 3456")
    Booking.create!(resource: car, user: user, destination: "Town",
                    start_at: 6.hours.ago, end_at: 2.hours.ago, status: "awaiting_return",
                    start_mileage: 1000, checked_in_at: 6.hours.ago)
    get kiosk_path(last4: "3456")
    assert_match I18n.t("reservations.completion.end_button"), @response.body
  end
end
