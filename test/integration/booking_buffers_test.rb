require "test_helper"

# The check-out / check-in buffers widen the QR action window: a driver can start
# a trip early and return late by the configured minutes.
class BookingBuffersTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def car(rules: {})
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km",
                              sort_order: 1, booking_rules: rules)
    c = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    c.create_resource_stat!(data: { "mileage" => 1000 })
    c
  end

  def user
    @user ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                           name: "Dan", email: "d#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  # Even with the buffer off, the scan shows the booking and when it can start,
  # rather than telling the person holding it that there is no reservation.
  test "with the buffer turned off, a booking starting in 20 minutes is shown but not yet startable" do
    c = car(rules: { "checkout" => { "buffer_minutes" => 0 } })
    Booking.create!(resource: c, user: user, destination: "Town",
                    start_at: 20.minutes.from_now, end_at: 3.hours.from_now, status: "active")
    get vehicle_scan_path(c.qr_token)

    assert_no_match(/#{Regexp.escape(I18n.t("reservations.status.no_active"))}/, @response.body)
    assert_match I18n.t("reservations.status.next_reservation"), @response.body
    assert_match I18n.t("reservations.status.starts_later", time: 20.minutes.from_now.strftime("%H:%M")),
                 @response.body
    assert_no_match(/#{Regexp.escape(I18n.t("reservations.check_in.button"))}/, @response.body)
  end

  test "by default a booking starting in 20 minutes can already be checked out" do
    c = car
    Booking.create!(resource: c, user: user, destination: "Town",
                    start_at: 20.minutes.from_now, end_at: 3.hours.from_now, status: "active")
    get vehicle_scan_path(c.qr_token)
    assert_match I18n.t("reservations.check_in.button"), @response.body
  end

  test "a 30-min check-out buffer lets a booking starting in 20 minutes be checked out" do
    c = car(rules: { "checkout" => { "buffer_minutes" => 30 } })
    Booking.create!(resource: c, user: user, destination: "Town",
                    start_at: 20.minutes.from_now, end_at: 3.hours.from_now, status: "active")
    get vehicle_scan_path(c.qr_token)
    assert_match I18n.t("reservations.check_in.button"), @response.body
  end

  test "a 10-min late-return buffer keeps a just-ended trip returnable" do
    c = car(rules: { "checkin" => { "buffer_minutes" => 10 } })
    Booking.create!(resource: c, user: user, destination: "Town",
                    start_at: 2.hours.ago, end_at: 5.minutes.ago, status: "awaiting_return",
                    checked_in_at: 2.hours.ago, start_mileage: 1000)
    get vehicle_scan_path(c.qr_token)
    assert_match I18n.t("reservations.completion.end_button"), @response.body
  end

  # A late return must stay closeable however late it is, or the trip keeps
  # running and the extra hours are billed to whoever scans next.
  test "a trip long past its end is still returnable, even with the buffer off" do
    c = car(rules: { "checkin" => { "buffer_minutes" => 0 } })
    Booking.create!(resource: c, user: user, destination: "Town",
                    start_at: 2.days.ago, end_at: 30.hours.ago, status: "awaiting_return",
                    checked_in_at: 2.days.ago, start_mileage: 1000)
    get vehicle_scan_path(c.qr_token)
    assert_match I18n.t("reservations.completion.end_button"), @response.body
  end

  test "a trip three minutes past its end is still returnable" do
    c = car
    Booking.create!(resource: c, user: user, destination: "Town",
                    start_at: 2.hours.ago, end_at: 3.minutes.ago, status: "awaiting_return",
                    checked_in_at: 2.hours.ago, start_mileage: 1000)
    get vehicle_scan_path(c.qr_token)
    assert_match I18n.t("reservations.completion.end_button"), @response.body
  end

  test "an idle car with no open trip still reports no active reservation" do
    c = car
    get vehicle_scan_path(c.qr_token)
    assert_match I18n.t("reservations.status.no_active"), @response.body
  end
end
