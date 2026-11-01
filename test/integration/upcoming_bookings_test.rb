require "test_helper"

# The dashboard shows the current user's future reservations as small cards that
# link to editing that booking.
class UpcomingBookingsTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def make_user(name: "Dan")
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                 name: name, email: "u#{SecureRandom.hex(6)}@example.com", user_type: "resident")
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    end
  end

  def booking_for(user, start_at:, end_at:, destination: "Town", status: "active")
    Booking.create!(resource: car, user: user, start_at: start_at, end_at: end_at,
                    status: status, destination: destination)
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "a future booking appears as a card linking to its edit page" do
    user = make_user
    future = booking_for(user, start_at: 2.days.from_now, end_at: 2.days.from_now + 3.hours)
    sign_in(user)

    get root_path

    assert_response :success
    assert_match I18n.t("calendar.upcoming.heading"), @response.body
    assert_select "a[href=?]", edit_booking_path(future)
  end

  test "past and other users' bookings are not shown" do
    user = make_user
    other = make_user(name: "Someone Else")
    past = booking_for(user, start_at: 2.days.ago, end_at: 2.days.ago + 2.hours, status: "returned")
    theirs = booking_for(other, start_at: 3.days.from_now, end_at: 3.days.from_now + 2.hours)
    sign_in(user)

    get root_path

    assert_select "a[href=?]", edit_booking_path(past), false
    assert_select "a[href=?]", edit_booking_path(theirs), false
  end

  test "no upcoming section when the user has none" do
    sign_in(make_user)
    get root_path
    assert_no_match(/#{Regexp.escape(I18n.t("calendar.upcoming.heading"))}/, @response.body)
  end
end
