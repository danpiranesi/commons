require "test_helper"

class ReservationCompletionServiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  # Freeze time so proration math (completed_at vs end_at) is deterministic.
  setup { freeze_time }
  teardown { travel_back }

  # ── Scenario builders ────────────────────────────────────────────────

  def make_user(type: "resident")
    User.create!(
      discourse_id: SecureRandom.random_number(1_000_000_000),
      name: "Test User",
      email: "u#{SecureRandom.hex(6)}@example.com",
      user_type: type
    )
  end

  def make_resource(billing_type:, name: "Res", start_odometer: nil,
                    hour_rate: 10, day_rate: 0, km_rate: 2.5, min_charge: 0, status: "active")
    rt = ResourceType.create!(name: "#{name}Type-#{SecureRandom.hex(3)}",
                              billing_type: billing_type, sort_order: 99)
    resource = Resource.create!(name: "#{name}-#{SecureRandom.hex(3)}", status: status, resource_type: rt)
    unless billing_type == "free"
      resource.resource_prices.create!(user_type: "resident", hour_rate: hour_rate,
                                       day_rate: day_rate, km_rate: km_rate, min_charge: min_charge)
    end
    resource.create_resource_stat!(data: { "mileage" => start_odometer }) unless start_odometer.nil?
    resource
  end

  # Default: a booking that started `hours` ago and is booked to end now, so a
  # completion "now" is on-time and bills the full booked window. Pass start_at/
  # end_at explicitly to exercise early/late returns.
  def make_booking(resource:, user:, hours: 2, status: "active", destination: "Test",
                   start_at: nil, end_at: nil)
    start_at ||= Time.current - hours.hours
    end_at   ||= Time.current
    Booking.create!(
      resource: resource, user: user,
      start_at: start_at, end_at: end_at,
      status: status,
      destination: resource.tracks_mileage? ? destination : nil
    )
  end

  # ── Per-distance (car) happy path ────────────────────────────────────

  test "per_day_and_km completion charges time + km, marks returned, updates odometer" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user, hours: 2)

    result = nil
    assert_enqueued_email_with ReceiptMailer, :completion, args: [booking] do
      result = ReservationCompletionService.call(booking: booking, ending_reading: 1150)
    end

    assert result.success?, "expected success, got #{result.error.inspect}"
    # time: 2h * 10 = 20 ; km: (1150-1000) * 2.5 = 375 ; total 395
    assert_equal 395.0, result.amount.to_f
    assert_equal 20.0, result.breakdown.time_cost.to_f
    assert_equal 375.0, result.breakdown.km_cost.to_f

    booking.reload
    assert_equal "returned", booking.status
    assert_equal 1150, booking.end_mileage
    assert_equal 1000, booking.start_mileage
    assert_equal 395.0, booking.total_amount.to_f
    assert_not_nil booking.completed_at

    # Odometer advanced on the resource itself
    assert_equal 1150, ResourceStat.find_by(resource_id: car.id).mileage
  end

  test "per_day_and_km deducts the charge from the member's ledger (negative sign)" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user, hours: 2)

    assert_equal 0, user.account.balance.to_f
    result = ReservationCompletionService.call(booking: booking, ending_reading: 1150)

    assert result.success?
    txn = booking.reload.billing_transaction
    assert_not_nil txn
    assert_equal(-395.0, txn.amount.to_f)
    assert_equal(-395.0, user.account.reload.balance.to_f)
  end

  # ── Per-time (no odometer) ───────────────────────────────────────────

  test "per_day completion charges time only and needs no odometer" do
    user = make_user
    bike = make_resource(billing_type: "per_day", name: "Bike")
    booking = make_booking(resource: bike, user: user, hours: 2)

    result = ReservationCompletionService.call(booking: booking) # no ending_reading

    assert result.success?, result.error.inspect
    assert_equal 20.0, result.amount.to_f
    assert_equal 0.0, result.breakdown.km_cost.to_f
    assert_equal "returned", booking.reload.status
  end

  # ── Free resource ────────────────────────────────────────────────────

  test "free resource completes at zero cost and writes no ledger transaction" do
    user = make_user
    room = make_resource(billing_type: "free", name: "Room")
    booking = make_booking(resource: room, user: user, hours: 3)

    result = ReservationCompletionService.call(booking: booking)

    assert result.success?
    assert_equal 0.0, result.amount.to_f
    assert_nil booking.reload.billing_transaction
    assert_equal 0.0, user.account.reload.balance.to_f
    assert_equal "returned", booking.status
  end

  # ── Odometer validation ──────────────────────────────────────────────

  test "per_day_and_km without a reading fails with :missing_reading" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user)

    result = ReservationCompletionService.call(booking: booking, ending_reading: nil)

    assert result.failure?
    assert_equal :missing_reading, result.error
    assert_equal "active", booking.reload.status
  end

  test "reading below the current odometer fails with :reading_too_low" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user)

    result = ReservationCompletionService.call(booking: booking, ending_reading: 900)

    assert result.failure?
    assert_equal :reading_too_low, result.error
    assert_equal 1000, result.meta[:current]
    assert_equal "active", booking.reload.status
  end

  test "implausible delta is flagged, not silently charged" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user)

    # 1000 -> 5000 = 4000 km, over the 2000 cap
    result = ReservationCompletionService.call(booking: booking, ending_reading: 5000)

    assert result.failure?
    assert_equal :reading_implausible, result.error
    assert_equal 4000, result.meta[:delta]
    assert_equal "active", booking.reload.status
    assert_nil booking.completed_at
  end

  test "implausible delta proceeds when explicitly confirmed with allow_high_delta" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user)

    result = ReservationCompletionService.call(booking: booking, ending_reading: 5000, allow_high_delta: true)

    assert result.success?
    assert_equal "returned", booking.reload.status
    assert_equal 5000, booking.end_mileage
  end

  # ── Idempotency ──────────────────────────────────────────────────────

  test "completing an already-returned booking is an idempotent no-op failure" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user)

    first = ReservationCompletionService.call(booking: booking, ending_reading: 1100)
    assert first.success?

    second = ReservationCompletionService.call(booking: booking.reload, ending_reading: 1200)
    assert second.failure?
    assert_equal :already_completed, second.error
    # No double charge
    assert_equal 1, booking.user.account.transactions.count
    assert_equal 1100, ResourceStat.find_by(resource_id: car.id).mileage
  end

  # ── Resource status must not block ending ────────────────────────────

  test "ending works even when the resource has been marked unavailable" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000, status: "unavailable")
    booking = make_booking(resource: car, user: user)

    result = ReservationCompletionService.call(booking: booking, ending_reading: 1050)

    assert result.success?, result.error.inspect
    assert_equal "returned", booking.reload.status
  end

  # ── Tolls + accessories (full basket) ────────────────────────────────

  test "tolls and accessories are billed into the parent completion" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user, hours: 2)

    # A Toll accessory priced at 50/unit, quantity 2 → 100
    toll_type = ResourceType.create!(name: "Toll", billing_type: "free", sort_order: 100)
    toll = Resource.create!(name: "Storebælt", status: "active", resource_type: toll_type)
    toll.resource_prices.create!(user_type: "resident", hour_rate: 50, day_rate: 0, km_rate: 0, min_charge: 0)
    booking.booking_accessories.create!(accessory: toll, quantity: 2)

    # A non-toll accessory (per_day, 5/hr → 2h = 10) as a shadow booking
    acc = make_resource(billing_type: "per_day", name: "ChildSeat", hour_rate: 5, km_rate: 0)
    shadow = Booking.create!(resource: acc, user: user, parent_booking: booking,
                             start_at: booking.start_at, end_at: booking.end_at, status: "active")

    result = ReservationCompletionService.call(booking: booking, ending_reading: 1100)

    assert result.success?, result.error.inspect
    # time 20 + km (100*2.5=250) + toll 100 + accessory 10 = 380
    assert_equal 100.0, result.breakdown.toll_cost.to_f
    assert_equal 10.0, result.breakdown.accessory_cost.to_f
    assert_equal 380.0, result.amount.to_f

    # Shadow accessory booking is closed and not separately charged
    assert_equal "returned", shadow.reload.status
    assert_equal 1, user.account.reload.transactions.count
  end

  test "stores the itemized breakdown so a receipt's line items sum to the total" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user, hours: 2)

    result = ReservationCompletionService.call(booking: booking, ending_reading: 1100)
    assert result.success?

    stored = booking.reload.charge_breakdown_struct
    assert_not_nil stored, "breakdown should be persisted at completion"
    assert_equal booking.total_amount, stored.total, "line items must sum to total_amount"
    assert_equal result.breakdown.total, stored.total
  end

  # ── Proration on early / late return ─────────────────────────────────

  test "early return is prorated to actual elapsed time" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    # Booked 4h (started 1h ago, ends in 3h); returning now = 1h actually used.
    booking = make_booking(resource: car, user: user,
                           start_at: 1.hour.ago, end_at: 3.hours.from_now)

    result = ReservationCompletionService.call(booking: booking, ending_reading: 1010)

    assert result.success?, result.error.inspect
    # time: 1h * 10 = 10 (not 40) ; km: 10 * 2.5 = 25 ; total 35
    assert_equal 10.0, result.breakdown.time_cost.to_f
    assert_equal 35.0, result.amount.to_f
    assert_equal 1.0, booking.reload.billed_hours
    # Ledger text reflects the billed (elapsed) hours, not the 4h booked window.
    assert_match "(1.0t)", booking.billing_transaction.description
  end

  # Keeping a car past its slot is billed for the time actually held, beyond a
  # short grace period (BookingRules#overdue_after_minutes, default 10 min).
  test "late return is billed for the extra time it was held" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user, hours: 2) # booked 2h, ends now

    travel 1.hour # complete an hour late

    result = ReservationCompletionService.call(booking: booking, ending_reading: 1010)

    assert result.success?
    # billed the 3h actually held (30), not the booked 2h
    assert_equal 30.0, result.breakdown.time_cost.to_f
    assert_equal 3.0, booking.reload.billed_hours
  end

  test "a return inside the grace period is not surcharged" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user, hours: 2)

    travel 5.minutes # inside the 10-minute grace

    result = ReservationCompletionService.call(booking: booking, ending_reading: 1010)

    assert result.success?
    assert_equal 20.0, result.breakdown.time_cost.to_f
    assert_equal 2.0, booking.reload.billed_hours
  end

  test "receipt breakdown matches the prorated amount actually charged" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user,
                           start_at: 1.hour.ago, end_at: 3.hours.from_now)

    ReservationCompletionService.call(booking: booking, ending_reading: 1010)

    # Mailer recomputes via PricingCalculator on the persisted booking; must equal
    # the stored total (prorated), not the booked-duration price.
    mailer_breakdown = PricingCalculator.new(
      booking.reload, start_odometer: booking.start_mileage, ending_reading: booking.end_mileage
    ).breakdown
    assert_equal booking.total_amount.to_f, mailer_breakdown.total.to_f
    assert_equal 35.0, mailer_breakdown.total.to_f
  end

  # ── Transaction atomicity ────────────────────────────────────────────

  test "a failure during ledger write rolls back the whole completion" do
    user = make_user
    car  = make_resource(billing_type: "per_day_and_km", start_odometer: 1000)
    booking = make_booking(resource: car, user: user)

    # Force the ledger write to blow up. The service resolves the account via
    # booking.user.account (cached), so a singleton override on that instance is hit.
    account = booking.user.account
    def account.transactions
      raise ActiveRecord::RecordInvalid.new(Transaction.new)
    end

    result = ReservationCompletionService.call(booking: booking, ending_reading: 1100)
    assert result.failure?
    assert_equal :persist_failed, result.error

    booking.reload
    assert_equal "active", booking.status, "booking must not be completed on rollback"
    assert_nil booking.total_amount
    assert_nil booking.completed_at
    # Odometer must not have advanced
    assert_equal 1000, ResourceStat.find_by(resource_id: car.id).mileage
    assert_equal 0, Transaction.where(account_id: account.id).count
  end

  # ── Shorten-penalty floor flows into the charge ──────────────────────

  test "a billed_until floor is charged even when the trip is returned earlier" do
    user = make_user
    # Hourly-priced resource so time is the whole charge: 10 kr/hour.
    bike = make_resource(billing_type: "per_day", hour_rate: 10, day_rate: 0, km_rate: 0)
    # Booked 10:00→14:00 but shortened to 12:00 with a 2h penalty floor at 14:00.
    booking = make_booking(resource: bike, user: user,
                           start_at: Time.current - 2.hours, end_at: Time.current)
    booking.update!(billed_until: Time.current + 2.hours) # floor 2h past the (new) end

    result = ReservationCompletionService.call(booking: booking)
    assert result.success?
    # Billed from start to the floor = 4 hours × 10 kr = 40, not the 2h actually used.
    assert_equal 40.0, result.amount.to_f, "charged to the penalty floor"
  end
end
