require "test_helper"

# The fast bruger hold gives a car's regular driver first claim on it, up to the
# Saturday-12:00 checkpoint before the week in question. After that the car is
# open to everyone.
class RegularUserHoldTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  teardown { travel_back }

  def member(name)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                 name: name, email: "#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  def car(regular_user)
    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active",
                     resource_type: rt, regular_user: regular_user)
  end

  # Monday of a week whose Saturday-noon checkpoint is 2026-09-05 12:00.
  WEEK_MONDAY = Date.new(2026, 9, 7)

  test "held for the regular driver before the Saturday deadline" do
    rikke = member("Rikke")
    sandra = member("Sandra")
    c = car(rikke)

    travel_to Time.zone.local(2026, 9, 4, 10, 0) do
      assert c.held_for?(WEEK_MONDAY.in_time_zone.change(hour: 9),
                         WEEK_MONDAY.in_time_zone.change(hour: 11), sandra)
    end
  end

  test "open to everyone once the Saturday deadline has passed" do
    rikke = member("Rikke")
    sandra = member("Sandra")
    c = car(rikke)

    travel_to Time.zone.local(2026, 9, 5, 12, 30) do
      assert_not c.held_for?(WEEK_MONDAY.in_time_zone.change(hour: 9),
                             WEEK_MONDAY.in_time_zone.change(hour: 11), sandra)
    end
  end

  # One Monday trip by the regular driver must not lock the car to them for the
  # whole week once the deadline has passed.
  test "a booking by the regular driver does not re-lock the rest of the week" do
    rikke = member("Rikke")
    sandra = member("Sandra")
    c = car(rikke)
    Booking.create!(resource: c, user: rikke, destination: "Town", status: "active",
                    start_at: WEEK_MONDAY.in_time_zone.change(hour: 8),
                    end_at: WEEK_MONDAY.in_time_zone.change(hour: 10))

    travel_to Time.zone.local(2026, 9, 5, 12, 30) do
      wednesday = WEEK_MONDAY + 2
      assert_not c.held_for?(wednesday.in_time_zone.change(hour: 9),
                             wednesday.in_time_zone.change(hour: 11), sandra)
    end
  end

  test "the regular driver is never held out of their own car" do
    rikke = member("Rikke")
    c = car(rikke)

    travel_to Time.zone.local(2026, 9, 4, 10, 0) do
      assert_not c.held_for?(WEEK_MONDAY.in_time_zone.change(hour: 9),
                             WEEK_MONDAY.in_time_zone.change(hour: 11), rikke)
    end
  end
end
