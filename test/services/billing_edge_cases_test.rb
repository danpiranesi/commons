require "test_helper"

# Billing behaviour at the edges: corrections, repeated completions, handovers
# between drivers, and shortened trips. Every figure here is arithmetic on a
# frozen clock, so a change in the charge shows up as a failing number rather
# than a rounding argument.
class BillingEdgeCasesTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # 5 kr/hour, 1 kr/km — round numbers so every expectation is checkable by hand.
  HOUR_RATE = 5
  KM_RATE   = 1

  setup do
    BillingCategory.seed_defaults!
    freeze_time
  end

  teardown { travel_back }

  def member(name = "Medlem", category_key: "member", user_type: "resident")
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{SecureRandom.hex(5)}@example.com", user_type: user_type,
                 billing_category: category_key && BillingCategory.find_by(key: category_key))
  end

  def car(odometer: 10_000)
    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    c = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    c.create_resource_stat!(data: { "mileage" => odometer })
    ResourcePrice.create!(resource: c, user_type: "resident", hour_rate: HOUR_RATE, day_rate: 0,
                          km_rate: KM_RATE, min_charge: 0, day_cap_hours: 16)
    c
  end

  # A finished 2-hour trip, ended exactly on time so no late-return hours creep in.
  def completed_trip(user:, resource:, km: 100, group: nil)
    booking = Booking.create!(resource: resource, user: user, billing_group: group,
                              destination: "Town", status: "awaiting_return",
                              start_at: 2.hours.ago, end_at: Time.current,
                              checked_in_at: 2.hours.ago, start_mileage: 10_000)
    ReservationCompletionService.call(booking: booking, ending_reading: 10_000 + km)
    booking.reload
  end

  def group_for(category_key, user)
    group = BillingGroup.create!(name: "Gruppe-#{SecureRandom.hex(3)}", code: SecureRandom.hex(4),
                                 billing_category: BillingCategory.find_by(key: category_key),
                                 active: true)
    BillingGroupMembership.create!(user: user, billing_group: group)
    group
  end

  # ── Corrections ───────────────────────────────────────────────────────

  test "a correction re-applies the member's rate instead of dropping to the plain one" do
    user = member(category_key: "perma") # multiplier x2
    trip = completed_trip(user: user, resource: car, km: 100)
    assert_equal 220, trip.total_amount.to_f, "2h x 5 + 100km x 1, doubled"

    ReservationCorrectionService.call(booking: trip, ending_reading: 10_120)
    trip.reload

    assert_equal 260, trip.total_amount.to_f, "corrected to 120km: (10 + 120) x 2"
  end

  test "a correction re-freezes the rate, so base and charged still reconcile" do
    user = member(category_key: "perma")
    trip = completed_trip(user: user, resource: car, km: 100)

    ReservationCorrectionService.call(booking: trip, ending_reading: 10_120)
    trip.reload
    rate = trip.billing_rate_struct

    assert_equal 130, rate.base.to_f,    "the sheet's base column must move with the correction"
    assert_equal 260, rate.charged.to_f
    assert_equal 120, rate.km
    assert_equal trip.total_amount.to_f, rate.charged.to_f
  end

  test "correcting an invoiced trip posts nothing to a personal ledger" do
    user = member(category_key: "hp") # collection: invoice
    trip = completed_trip(user: user, resource: car, km: 100)
    assert_equal 0, Transaction.where(booking: trip).count, "invoiced trips have no ledger entry"

    ReservationCorrectionService.call(booking: trip, ending_reading: 10_120)

    assert_equal 0, Transaction.where(booking: trip).count,
                 "a correction must not hand an invoiced member a credit they were never charged"
  end

  test "correcting a bank-transfer trip leaves the ledger owing exactly the new amount" do
    user = member(category_key: "member") # collection: bank
    trip = completed_trip(user: user, resource: car, km: 100)
    assert_equal(-110, Transaction.where(booking: trip).sum(:amount).to_f)

    ReservationCorrectionService.call(booking: trip, ending_reading: 10_120)
    trip.reload

    assert_equal 130, trip.total_amount.to_f
    assert_equal(-130, Transaction.where(booking: trip).sum(:amount).to_f,
                 "the offsetting entry must bring the ledger to the corrected amount")
  end

  test "correcting a state-rate trip charges the state rate, not the ordinary calculation" do
    user  = member
    group = group_for("ks_arbejdsgruppe", user) # per_km, 3.94 kr/km
    trip  = completed_trip(user: user, resource: car, km: 100, group: group)
    assert_equal 394, trip.total_amount.to_f

    ReservationCorrectionService.call(booking: trip, ending_reading: 10_120)
    trip.reload

    assert_equal 472.8, trip.total_amount.to_f, "120 km x 3.94"
  end

  # ── Repeated completion ───────────────────────────────────────────────

  test "completing the same trip twice charges for it once" do
    user = member
    c    = car
    booking = Booking.create!(resource: c, user: user, destination: "Town",
                              status: "awaiting_return", start_at: 2.hours.ago,
                              end_at: Time.current, checked_in_at: 2.hours.ago,
                              start_mileage: 10_000)

    # Two requests that BOTH loaded the booking while it was still open — a
    # double-tapped confirm, or a retry after the first response was lost. Both
    # copies must be read up front, or this only tests sequential idempotency.
    copy_a = Booking.find(booking.id)
    copy_b = Booking.find(booking.id)

    first  = ReservationCompletionService.call(booking: copy_a, ending_reading: 10_100)
    second = ReservationCompletionService.call(booking: copy_b, ending_reading: 10_100)

    assert first.success?
    assert second.failure?
    assert_equal :already_completed, second.error
    assert_equal 1, Transaction.where(booking: booking).count
    assert_equal(-110, Transaction.where(booking: booking).sum(:amount).to_f)
  end

  # ── Handover between drivers ──────────────────────────────────────────

  test "checking out early does not close the trip of whoever is still out in the car" do
    out    = member("Ude")
    next_up = member("Næste")
    c = car

    # Still legitimately out: the booking runs for another hour.
    live = Booking.create!(resource: c, user: out, destination: "Town", status: "awaiting_return",
                           start_at: 4.hours.ago, end_at: 1.hour.from_now,
                           checked_in_at: 4.hours.ago, start_mileage: 10_000)
    # The next driver's slot starts soon, and the check-out buffer lets them scan now.
    soon = Booking.create!(resource: c, user: next_up, destination: "Town", status: "active",
                           start_at: 1.hour.from_now, end_at: 4.hours.from_now)

    ReservationCheckInService.call(booking: soon, starting_reading: 10_030, checked_in_by: next_up)
    live.reload

    assert_equal "awaiting_return", live.status, "a trip inside its window must not be force-closed"
    assert_nil live.total_amount, "and must certainly not be billed mid-journey"
  end

  test "checking in still closes a trip that really was forgotten" do
    forgetful = member("Glemsom")
    next_up   = member("Næste")
    c = car

    forgotten = Booking.create!(resource: c, user: forgetful, destination: "Town",
                                status: "awaiting_return", start_at: 8.hours.ago,
                                end_at: 2.hours.ago, checked_in_at: 8.hours.ago,
                                start_mileage: 10_000)
    nxt = Booking.create!(resource: c, user: next_up, destination: "Town", status: "active",
                          start_at: Time.current, end_at: 3.hours.from_now)

    ReservationCheckInService.call(booking: nxt, starting_reading: 10_050, checked_in_by: next_up)

    assert_equal "returned", forgotten.reload.status
    assert_equal 50, forgotten.km_driven
  end

  # ── Shortening a live trip ────────────────────────────────────────────

  test "the shorten penalty is not thrown away by handing the car back early" do
    user = member
    c    = car
    booking = Booking.create!(resource: c, user: user, destination: "Town", status: "active",
                              start_at: 1.hour.ago, end_at: 5.hours.from_now,
                              checked_in_at: 1.hour.ago, start_mileage: 10_000)

    was = booking.end_at
    booking.update!(end_at: 1.hour.from_now)      # cut a live 6-hour booking to 2 hours
    booking.apply_edit_penalty!(previous_end: was)
    booking.reload
    assert_equal 3.hours.from_now, booking.billed_until, "2h penalty on top of the new end"

    # …then hand it back almost immediately.
    booking.completed_at = 10.minutes.from_now

    assert_equal 4.0, booking.billed_hours,
                 "billed from start to the penalty floor, not to the early return"
  end

  test "a correction re-prices at the rate the trip was completed at, not today's" do
    user = member(category_key: "member")     # x1 when the trip was taken
    trip = completed_trip(user: user, resource: car, km: 100)
    assert_equal 110, trip.total_amount.to_f

    # The member is later moved onto a double rate.
    user.update!(billing_category: BillingCategory.find_by(key: "perma"))

    ReservationCorrectionService.call(booking: trip, ending_reading: 10_120)
    trip.reload

    assert_equal 130, trip.total_amount.to_f,
                 "correcting an old trip must not re-price it at the member's new category"
  end

  test "an ordinary early return is still only billed for the time used" do
    user = member
    c    = car
    booking = Booking.create!(resource: c, user: user, destination: "Town", status: "active",
                              start_at: 1.hour.ago, end_at: 5.hours.from_now,
                              checked_in_at: 1.hour.ago, start_mileage: 10_000)
    booking.completed_at = Time.current

    assert_nil booking.billed_until
    assert_equal 1.0, booking.billed_hours
  end
end
