require "test_helper"

# An early-returned booking stays on the grid as a muted marker for its elapsed
# portion, while the freed remainder is still bookable (overlap checks ignore
# returned bookings).
class ReturnedBookingGridTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { travel_to Time.zone.local(2026, 7, 15, 12, 0, 0) }
  teardown { travel_back }

  def user
    @user ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                           name: "Dan", email: "d#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    end
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "a returned booking shows a faded 'returned' marker instead of vanishing" do
    Booking.create!(resource: car, user: user, destination: "Town",
                    start_at: Time.zone.local(2026, 7, 15, 9, 0), end_at: Time.zone.local(2026, 7, 15, 17, 0),
                    status: "returned", completed_at: Time.zone.local(2026, 7, 15, 9, 30))
    sign_in(user)

    get calendar_path(date: "2026-07-15")

    assert_response :success
    assert_match I18n.t("calendar.week_grid.returned"), @response.body
    assert_match "09:00–09:30", @response.body      # elapsed portion, capped at completed_at
    assert_no_match(/09:00.{0,6}17:00/, @response.body) # not the full booked window
  end

  test "the freed remainder is still bookable (a new overlapping booking is allowed)" do
    Booking.create!(resource: car, user: user, destination: "Town",
                    start_at: Time.zone.local(2026, 7, 15, 9, 0), end_at: Time.zone.local(2026, 7, 15, 17, 0),
                    status: "returned", completed_at: Time.zone.local(2026, 7, 15, 9, 30))

    # A fresh booking overlapping the original window must validate — returned
    # bookings don't count toward the concurrency limit.
    fresh = Booking.new(resource: car, user: user, destination: "Errand",
                        start_at: Time.zone.local(2026, 7, 15, 11, 0), end_at: Time.zone.local(2026, 7, 15, 13, 0),
                        status: "active")
    assert fresh.valid?, fresh.errors.full_messages.to_sentence
  end
end
