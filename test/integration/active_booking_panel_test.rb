require "test_helper"

# The pinned active-booking panel on the dashboard: shown only for a live
# booking, ends through the shared service, and hides the call block when there
# is no phone number.
class ActiveBookingPanelTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def make_user(name: "Alice", phone: nil)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                 name: name, email: "u#{SecureRandom.hex(6)}@example.com",
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

  def booking_for(user, start_at: 2.hours.ago, end_at: Time.current, status: "active")
    Booking.create!(resource: car, user: user, start_at: start_at, end_at: end_at,
                    status: status, destination: "Town")
  end

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  test "panel is hidden when the user has no active booking" do
    sign_in(make_user)
    get root_path
    assert_response :success
    assert_select "form[action=?]", reservation_completion_path, false
  end

  test "panel shows and ending through it returns to the dashboard" do
    user = make_user
    booking = booking_for(user)
    sign_in(user)

    get root_path
    assert_response :success
    assert_match I18n.t("calendar.active_panel.heading"), @response.body
    # Fresh car → panel first offers check-in, not end.
    assert_select "form[action=?]", reservation_check_in_path

    post reservation_check_in_path, params: {
      token: car.qr_token, booking_id: booking.id, starting_reading: 1000, return_to: root_path
    }

    get root_path
    assert_select "form[action=?]", reservation_completion_path

    post reservation_completion_path, params: {
      token: car.qr_token, booking_id: booking.id, ending_reading: 1100, return_to: root_path, confirmed: "1"
    }
    assert_redirected_to root_path
    assert_equal "returned", booking.reload.status
  end

  test "close-transfer call block appears only when both members have a phone" do
    current = make_user(name: "Alice", phone: "+45 11 11 11 11")
    nexter  = make_user(name: "Bob",   phone: "+45 22 22 22 22")
    booking_for(current)
    # next booking starts 15 min after this one ends → within the 30-min window
    booking_for(nexter, start_at: 15.minutes.from_now, end_at: 2.hours.from_now)
    sign_in(current)

    get root_path
    assert_match I18n.t("reservations.handoff.call", phone: "+45 22 22 22 22"), @response.body
    assert_select "a[href=?]", "tel:+4522222222"
  end

  test "close-transfer call block is hidden when the next member has no phone" do
    current = make_user(name: "Alice", phone: "+45 11 11 11 11")
    nexter  = make_user(name: "Bob",   phone: nil)
    booking_for(current)
    booking_for(nexter, start_at: 15.minutes.from_now, end_at: 2.hours.from_now)
    sign_in(current)

    get root_path
    # Bob's name is in the week grid anyway; the tel: link is the call block.
    assert_select "a[href^='tel:']", false, "call block must hide when the next member has no phone"
  end

  # Getting back after the booked end must still leave a way to end the trip on
  # the dashboard, hours late included — the same guarantee the QR page carries.
  test "panel still offers the end form when the driver is back late" do
    user = make_user
    [3.minutes, 25.minutes, 3.hours, 2.days].each do |late|
      b = booking_for(user, start_at: 4.hours.ago - late, end_at: Time.current - late,
                            status: "awaiting_return")
      b.update!(checked_in_at: b.start_at, start_mileage: 1000)
      sign_in user
      get root_path
      assert_match I18n.t("reservations.completion.end_button"), @response.body,
                   "no end form on the panel #{late.inspect} late"
      b.update!(status: "returned", completed_at: Time.current)
    end
  end
end
