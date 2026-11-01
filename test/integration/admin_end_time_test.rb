require "test_helper"

# An admin can change when a reservation ends at any point in its life: move the
# end time of a trip that is out or booked, or correct the actual return time of
# one already closed -- and in the second case the charge follows.
class AdminEndTimeTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    freeze_time
    BillingCategory.seed_defaults!
    @admin  = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Anna",
                           email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident", admin: true)
    @driver = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Jake",
                           email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident",
                           billing_category: BillingCategory.find_by(key: "member"))
    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    @car = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    @car.create_resource_stat!(data: { "mileage" => 10_100 })
    ResourcePrice.create!(resource: @car, user_type: "resident", hour_rate: 5, day_rate: 0,
                          km_rate: 1, min_charge: 0, day_cap_hours: 16)
    get "/test/sign_in/#{@admin.id}"
  end

  teardown { travel_back }

  # ── Open bookings: the quick adjust on the booking page ───────────────

  test "an admin can move the end time of a trip that is out" do
    b = Booking.create!(resource: @car, user: @driver, destination: "Town", status: "awaiting_return",
                        start_at: 2.hours.ago, end_at: 2.hours.from_now,
                        checked_in_at: 2.hours.ago, start_mileage: 10_000)
    target = 5.hours.from_now.change(min: 0)
    patch adjust_end_booking_path(b), params: {
      booking_end: { date: target.to_date.to_s, hour: target.hour, min: target.min }
    }
    assert_redirected_to booking_path(b)
    assert_equal target, b.reload.end_at
    assert_equal "awaiting_return", b.status, "adjusting the time must not end the trip"
  end

  test "the quick adjust carries no shorten penalty and clears an existing one" do
    b = Booking.create!(resource: @car, user: @driver, destination: "Town", status: "awaiting_return",
                        start_at: 1.hour.ago, end_at: 6.hours.from_now, billed_until: 4.hours.from_now,
                        checked_in_at: 1.hour.ago, start_mileage: 10_000)
    target = 1.hour.from_now.change(min: 0)
    patch adjust_end_booking_path(b), params: {
      booking_end: { date: target.to_date.to_s, hour: target.hour, min: target.min }
    }
    b.reload
    assert_equal target, b.end_at
    assert_nil b.billed_until, "the admin's time is the truth; no floor should survive"
  end

  test "the quick adjust is refused if it would collide with the next reservation" do
    b = Booking.create!(resource: @car, user: @driver, destination: "Town", status: "active",
                        start_at: 1.hour.from_now, end_at: 3.hours.from_now)
    Booking.create!(resource: @car, user: @admin, destination: "Town", status: "active",
                    start_at: 4.hours.from_now, end_at: 6.hours.from_now)
    target = 5.hours.from_now.change(min: 0)
    patch adjust_end_booking_path(b), params: {
      booking_end: { date: target.to_date.to_s, hour: target.hour, min: target.min }
    }
    assert_equal 3.hours.from_now, b.reload.end_at
    assert_match I18n.t("bookings.alerts.overlap"), flash[:alert]
  end

  test "a member cannot use the quick adjust" do
    b = Booking.create!(resource: @car, user: @driver, destination: "Town", status: "active",
                        start_at: 1.hour.from_now, end_at: 3.hours.from_now)
    get "/test/sign_in/#{@driver.id}"
    target = 5.hours.from_now
    patch adjust_end_booking_path(b), params: {
      booking_end: { date: target.to_date.to_s, hour: target.hour, min: 0 }
    }
    assert_equal 3.hours.from_now, b.reload.end_at
  end

  test "the booking page shows the adjust card to an admin for an open trip only" do
    open_trip = Booking.create!(resource: @car, user: @driver, destination: "Town", status: "active",
                                start_at: 1.hour.from_now, end_at: 3.hours.from_now)
    get booking_path(open_trip)
    assert_match I18n.t("bookings.show.adjust_end_card_title"), @response.body

    open_trip.update!(status: "returned", completed_at: Time.current, end_mileage: 10_100, total_amount: 20)
    get booking_path(open_trip)
    assert_no_match(/#{Regexp.escape(I18n.t("bookings.show.adjust_end_card_title"))}/, @response.body)
  end

  # ── Returned bookings: correcting the actual return time re-prices ────

  # Booked 06:00-16:00, closed by the next morning's scan at 09:45.
  def late_scanned_trip
    start = Time.zone.local(2026, 9, 2, 6, 0)
    b = Booking.create!(resource: @car, user: @driver, destination: "Town", status: "awaiting_return",
                        start_at: start, end_at: start + 10.hours,
                        checked_in_at: start, start_mileage: 10_000)
    travel_to(Time.zone.local(2026, 9, 3, 9, 45)) do
      ReservationCompletionService.call(booking: b, ending_reading: 10_100)
    end
    b.reload
  end

  test "correcting the return time re-prices the trip and posts the difference" do
    b = late_scanned_trip
    assert_equal 28.0, b.billed_hours, "06:00 to 09:45 next day is 27h45m, past the grace so rounded up"
    assert_equal 240.0, b.total_amount.to_f, "28h x 5 + 100 km"

    patch admin_booking_path(b), params: { booking: { completed_at: "2026-09-02T16:00" } }
    b.reload

    assert_equal Time.zone.local(2026, 9, 2, 16, 0), b.completed_at
    assert_equal 10.0, b.billed_hours
    assert_equal 150.0, b.total_amount.to_f, "10h x 5 + 100 km"
    assert_equal(-150.0, Transaction.where(booking: b).sum(:amount).to_f,
                 "the ledger must net to the corrected charge")
    assert_equal 100, b.km_driven, "correcting the time alone must not touch the distance"
  end

  test "return time and reading can be corrected together in one pass" do
    b = late_scanned_trip
    patch admin_booking_path(b), params: { booking: { completed_at: "2026-09-02T16:00", end_mileage: "10120" } }
    b.reload
    assert_equal 10.0, b.billed_hours
    assert_equal 120, b.km_driven
    assert_equal 170.0, b.total_amount.to_f, "10h x 5 + 120 km"
    assert_equal 2, Transaction.where(booking: b).count, "the original charge plus ONE offsetting entry"
  end

  test "a return time before the trip started is refused" do
    b = late_scanned_trip
    before = b.total_amount
    patch admin_booking_path(b), params: { booking: { completed_at: "2026-09-02T05:00" } }
    assert_response :unprocessable_entity
    assert_equal before, b.reload.total_amount
  end

  test "re-submitting the time already shown changes nothing" do
    b = late_scanned_trip
    shown = b.completed_at.strftime("%Y-%m-%dT%H:%M")
    assert_no_difference -> { Transaction.count } do
      patch admin_booking_path(b), params: { booking: { completed_at: shown } }
    end
  end
end
