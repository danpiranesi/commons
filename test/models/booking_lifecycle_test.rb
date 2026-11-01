require "test_helper"

# Rules for editing and extending a booking in progress: half-hour rounding, the
# shorten penalty (billing floor), the overdue flag, and the extension ceiling.
class BookingLifecycleTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def car(rules: {})
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km",
                              sort_order: 1, booking_rules: rules)
    c = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    c.resource_prices.create!(user_type: "resident", hour_rate: 5, day_rate: 0, km_rate: 0, min_charge: 0)
    c.create_resource_stat!(data: { "mileage" => 1000 })
    c
  end

  def user
    @user ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                           name: "Dan", email: "d#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  # start 3h ago, ends in `ends_in`, in progress.
  def in_progress(car, ends_in:)
    Booking.create!(resource: car, user: user, destination: "Town",
                    start_at: 3.hours.ago, end_at: ends_in, status: "active", start_mileage: 1000)
  end

  # ── Half-hour rounding with a grace ───────────────────────────
  # A 10:00 start booked to 14:00, returned early after `elapsed`.
  def returned_after(elapsed, rules: {})
    start = Time.zone.local(2026, 10, 1, 10, 0)
    Booking.new(resource: car(rules: rules), user: user, start_at: start, end_at: start + 4.hours,
                status: "returned", completed_at: start + elapsed)
  end

  test "minutes inside the grace round down to the half hour" do
    assert_equal 1.5, returned_after(1.hour + 40.minutes).billed_hours, "10 min into the block"
    assert_equal 1.5, returned_after(1.hour + 40.minutes + 59.seconds).billed_hours, "still minute 10"
  end

  test "from the minute after the grace it rounds up" do
    assert_equal 2.0, returned_after(1.hour + 41.minutes).billed_hours, "minute 11"
    assert_equal 2.0, returned_after(1.hour + 59.minutes).billed_hours
  end

  test "a very short trip still bills one block" do
    assert_equal 0.5, returned_after(4.minutes).billed_hours
  end

  test "the grace is configurable per type" do
    rules = { "checkin" => { "grace_minutes" => 0 } }
    assert_equal 2.0, returned_after(1.hour + 31.minutes, rules: rules).billed_hours
  end

  test "a late return inside the grace bills the booked end" do
    start = Time.zone.local(2026, 10, 1, 10, 0)
    b = Booking.new(resource: car, user: user, start_at: start, end_at: start + 2.hours,
                    status: "returned", completed_at: start + 2.hours + 9.minutes)
    assert_equal 2.0, b.billed_hours
    b.completed_at = start + 2.hours + 12.minutes
    assert_equal 2.5, b.billed_hours, "past the grace the late block is billed"
  end

  # ── Shorten penalty ────────────────────────────────────────────
  test "shortening an in-progress short booking sets a 2h billing floor" do
    c = car
    b = in_progress(c, ends_in: 5.hours.from_now) # 8h booked, under 24h
    previous_end = b.end_at
    b.update!(end_at: 1.hour.from_now)             # cut it short
    b.apply_edit_penalty!(previous_end: previous_end)

    assert_equal 3.hours.from_now, b.reload.billed_until, "floor is new end + 2h"
  end

  test "billed_hours honours the floor even when returned before it" do
    c = car
    b = in_progress(c, ends_in: 5.hours.from_now)
    previous_end = b.end_at
    b.update!(end_at: 1.hour.from_now)
    b.apply_edit_penalty!(previous_end: previous_end)

    # Return right at the new end (1h from now = 4h after start), but floor is at 3h from now (6h after start)
    b.update!(completed_at: 1.hour.from_now)
    assert_equal 6.0, b.billed_hours, "billed to the floor, not the early return"
  end

  test "the floor never charges past the original end" do
    c = car
    b = in_progress(c, ends_in: 1.hour.from_now) # short remaining window
    previous_end = b.end_at
    b.update!(end_at: 30.minutes.from_now)       # new end + 2h would exceed original end
    b.apply_edit_penalty!(previous_end: previous_end)

    assert_equal previous_end, b.reload.billed_until, "capped at the original end"
  end

  test "a long (>=24h) booking is exempt from the penalty" do
    c = car
    b = Booking.create!(resource: c, user: user, destination: "Town",
                        start_at: 2.hours.ago, end_at: 30.hours.from_now, status: "active", start_mileage: 1000)
    previous_end = b.end_at
    b.update!(end_at: 2.hours.from_now)
    b.apply_edit_penalty!(previous_end: previous_end)

    assert_nil b.reload.billed_until
  end

  test "a not-yet-started (future) booking is exempt" do
    c = car
    b = Booking.create!(resource: c, user: user, destination: "Town",
                        start_at: 2.hours.from_now, end_at: 8.hours.from_now, status: "active", start_mileage: 1000)
    previous_end = b.end_at
    b.update!(end_at: 4.hours.from_now)
    b.apply_edit_penalty!(previous_end: previous_end)

    assert_nil b.reload.billed_until, "penalty is in-progress only"
  end

  test "penalty_hours of 0 disables the penalty for that type" do
    c = car(rules: { "during" => { "allow_extension" => true, "edit_shorten_penalty_hours" => 0 } })
    b = in_progress(c, ends_in: 5.hours.from_now)
    previous_end = b.end_at
    b.update!(end_at: 1.hour.from_now)
    b.apply_edit_penalty!(previous_end: previous_end)

    assert_nil b.reload.billed_until
  end

  test "a state-rate (per_km) trip gets no time penalty" do
    c = car
    cat = BillingCategory.create!(key: "ks-#{SecureRandom.hex(3)}", name_da: "K/S", rate_mode: "per_km",
                                  rate_value: 4.0, collection: "invoice", section: 4)
    user.update!(billing_category: cat)
    b = in_progress(c, ends_in: 5.hours.from_now)
    previous_end = b.end_at
    b.update!(end_at: 1.hour.from_now)
    b.apply_edit_penalty!(previous_end: previous_end)

    assert_nil b.reload.billed_until
  end

  test "re-extending past the floor clears the penalty" do
    c = car
    b = in_progress(c, ends_in: 5.hours.from_now)
    previous_end = b.end_at
    b.update!(end_at: 1.hour.from_now)
    b.apply_edit_penalty!(previous_end: previous_end) # floor at 3h from now
    assert b.reload.billed_until

    # extend back out past the floor
    prev2 = b.end_at
    b.update!(end_at: 5.hours.from_now)
    b.apply_edit_penalty!(previous_end: prev2)
    assert_nil b.reload.billed_until
  end

  test "shortening again cannot lower an existing floor" do
    c = car
    b = in_progress(c, ends_in: 5.hours.from_now)
    p1 = b.end_at
    b.update!(end_at: 1.hour.from_now)
    b.apply_edit_penalty!(previous_end: p1)          # floor 3h from now
    floor1 = b.reload.billed_until

    p2 = b.end_at
    b.update!(end_at: 30.minutes.from_now)           # shorten more
    b.apply_edit_penalty!(previous_end: p2)
    assert_equal floor1, b.reload.billed_until, "floor stays; can't dodge by shortening again"
  end

  # ── Overdue ────────────────────────────────────────────────────
  test "overdue after the grace period, not before" do
    c = car # default 10-min grace
    b = in_progress(c, ends_in: 5.minutes.ago)
    refute b.overdue?, "within the 10-min grace"

    b.update!(end_at: 15.minutes.ago)
    assert b.overdue?, "past the grace"
  end

  test "a returned booking is never overdue" do
    c = car
    b = in_progress(c, ends_in: 1.hour.ago)
    b.update!(status: "returned", completed_at: 30.minutes.ago)
    refute b.overdue?
  end

  test "overdue grace is configurable per type" do
    c = car(rules: { "checkin" => { "overdue_after_minutes" => 30 } })
    b = in_progress(c, ends_in: 20.minutes.ago)
    refute b.overdue?, "still within a 30-min grace"
  end

  # ── Extension ceiling ──────────────────────────────────────────
  test "max_extension_end is the next booking's start" do
    c = car
    b = in_progress(c, ends_in: 2.hours.from_now)
    later = Booking.create!(resource: c, user: user, destination: "Later",
                            start_at: 4.hours.from_now, end_at: 6.hours.from_now, status: "active", start_mileage: 1000)
    assert_equal later.start_at, b.max_extension_end
  end

  test "max_extension_end is nil when nothing is booked ahead" do
    c = car
    b = in_progress(c, ends_in: 2.hours.from_now)
    assert_nil b.max_extension_end
  end
end
