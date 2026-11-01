require "test_helper"

# Repeating a slot across weekdays: the commuter case. The repeat must reach
# past the current week, and every booking must keep the picked hour (times are
# built in the app's zone, not the server's).
class RecurringBookingsTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                         name: "Jeanette", email: "#{SecureRandom.hex(4)}@example.com",
                         user_type: "resident")
    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    @car = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    get "/test/sign_in/#{@user.id}"
  end

  teardown { travel_back }

  def book(start_date, days:, weeks:, start_hour: 7, end_hour: 23, **extra)
    post bookings_path, params: {
      recurring: "1",
      recurring_days: days,
      recurring_weeks: weeks,
      booking_start: { date: start_date.to_s, hour: start_hour, min: 0 },
      booking_end:   { date: start_date.to_s, hour: end_hour, min: 0 },
      booking: { resource_id: @car.id, destination: "Hospital" }.merge(extra)
    }
  end

  test "a repeat reaches into next week, not just the current one" do
    travel_to Time.zone.local(2026, 9, 10, 6, 0) do   # Thursday
      book(Date.new(2026, 9, 10), days: %w[1 2 3 4 5], weeks: 2)

      created = Booking.where(user: @user, resource: @car).order(:start_at)
      # This week only Thu + Fri are left; next week is all five days.
      assert_equal 7, created.count
      assert_equal Date.new(2026, 9, 18), created.last.start_at.to_date
    end
  end

  test "every repeat keeps the hour the member picked" do
    travel_to Time.zone.local(2026, 9, 10, 6, 0) do
      book(Date.new(2026, 9, 10), days: %w[1 2 3 4 5], weeks: 2, start_hour: 7, end_hour: 23)

      Booking.where(user: @user, resource: @car).find_each do |b|
        assert_equal 7,  b.start_at.in_time_zone.hour, "start hour drifted on #{b.start_at}"
        assert_equal 23, b.end_at.in_time_zone.hour,   "end hour drifted on #{b.end_at}"
      end
    end
  end

  test "an evening return past 22:00 is accepted" do
    travel_to Time.zone.local(2026, 9, 10, 6, 0) do
      book(Date.new(2026, 9, 10), days: %w[4], weeks: 1, start_hour: 7, end_hour: 23)
      b = Booking.where(user: @user, resource: @car).first
      assert_equal 23, b.end_at.in_time_zone.hour
    end
  end

  test "the group a trip is booked for is carried onto every repeat" do
    category = BillingCategory.create!(key: "grp-#{SecureRandom.hex(3)}", name_da: "Gruppe",
                                       rate_mode: "multiplier", rate_value: 1.0)
    group = BillingGroup.create!(name: "Carpool", code: "carpool-#{SecureRandom.hex(3)}",
                                 billing_category: category, active: true)
    BillingGroupMembership.create!(user: @user, billing_group: group)

    travel_to Time.zone.local(2026, 9, 10, 6, 0) do
      book(Date.new(2026, 9, 10), days: %w[4 5], weeks: 1, billing_group_id: group.id)

      bookings = Booking.where(user: @user, resource: @car)
      assert bookings.any?
      assert bookings.all? { |b| b.billing_group_id == group.id },
             "every repeat should be charged to the group it was booked for"
    end
  end
end
