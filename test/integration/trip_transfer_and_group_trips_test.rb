require "test_helper"

# Moving a billed trip to another member or a work group, keeping group trips
# off the driver's own overview, and the end-of-trip confirm screen.
class TripTransferAndGroupTripsTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    BillingCategory.seed_defaults!
    travel_to Time.zone.local(2026, 10, 14, 12, 0)
  end

  teardown { travel_back }

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  def make_user(name, **attrs)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{name.downcase}#{SecureRandom.hex(3)}@example.com", user_type: "resident", **attrs)
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      c  = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
      c.resource_prices.create!(user_type: "resident", hour_rate: 5, day_rate: 0, km_rate: 1, min_charge: 0)
      c.create_resource_stat!(data: { "mileage" => 1000 })
      c
    end
  end

  def admin = @admin ||= make_user("Anna", admin: true)
  def workshop = @workshop ||= BillingGroup.create!(name: "Workshop", billing_category: BillingCategory.find_by!(key: "ks_arbejdsgruppe"))

  # 3h + 50 km at 5 kr/h and 1 kr/km = 65 kr, charged to the driver's ledger.
  def billed_trip(driver)
    b = Booking.create!(resource: car, user: driver, destination: "Town",
                        start_at: Time.zone.local(2026, 10, 10, 9), end_at: Time.zone.local(2026, 10, 10, 12),
                        status: "returned", completed_at: Time.zone.local(2026, 10, 10, 12),
                        start_mileage: 1000, end_mileage: 1050, total_amount: 65, billing_month: "202610")
    driver.account.transactions.create!(user: driver, booking: b, amount: -65, description: "charge")
    b
  end

  def ledger(user) = Transaction.where(user: user).sum(:amount).to_f

  # ── Moving a billed trip ───────────────────────────────────────
  test "a billed trip moves to another member: refunded to one, charged to the other" do
    emil, rikke = make_user("Emil"), make_user("Rikke")
    trip = billed_trip(emil)

    sign_in admin
    patch admin_booking_path(trip), params: { transfer: "1", target_user_id: rikke.id, billing_group_id: "" }
    assert_redirected_to edit_admin_booking_path(trip)

    assert_equal rikke, trip.reload.user
    assert_equal 0.0, ledger(emil)
    assert_equal(-65.0, ledger(rikke))
  end

  test "a billed trip moves onto a work group the driver is not in: driver refunded, group billed on the sheet" do
    emil = make_user("Emil")
    trip = billed_trip(emil)

    sign_in admin
    patch admin_booking_path(trip), params: { transfer: "1", target_user_id: emil.id, billing_group_id: workshop.id }

    trip.reload
    assert_equal workshop, trip.billing_group
    assert_equal 0.0, ledger(emil), "a group's trip is not on anyone's personal ledger"
    assert_equal "per_km", trip.billing_rate["mode"], "re-priced at the group's state rate"
  end

  test "a trip cannot be moved in a closed month" do
    emil, rikke = make_user("Emil"), make_user("Rikke")
    trip = billed_trip(emil)
    ClosedBillingMonth.create!(billing_month: "202610")

    sign_in admin
    patch admin_booking_path(trip), params: { transfer: "1", target_user_id: rikke.id }
    assert_equal emil, trip.reload.user
  end

  # ── Group trips on the member's own overview ───────────────────
  test "a group trip is listed apart on the driver's overview and not in their total" do
    emil = make_user("Emil")
    workshop.billing_group_memberships.create!(user: emil)
    Booking.create!(resource: car, user: emil, billing_group: workshop, destination: "Town",
                    start_at: Time.zone.local(2026, 10, 10, 9), end_at: Time.zone.local(2026, 10, 10, 12),
                    status: "returned", completed_at: Time.zone.local(2026, 10, 10, 12),
                    total_amount: 197, billing_month: "202610")

    sign_in emil
    get usage_path
    assert_match I18n.t("usage.show.group_trips_title"), @response.body
    assert_no_match(/197 kr/, @response.body)
  end

  # ── End-of-trip confirm screen ─────────────────────────────────
  test "the confirm screen says the trip has not ended yet" do
    emil = make_user("Emil")
    b = Booking.create!(resource: car, user: emil, destination: "Town", status: "awaiting_return",
                        start_at: 2.hours.ago, end_at: 1.hour.from_now, checked_in_at: 2.hours.ago, start_mileage: 1000)

    post reservation_completion_path, params: { token: car.qr_token, booking_id: b.id, ending_reading: 1030 }
    assert_match I18n.t("reservations.confirm.not_ended_title"), @response.body
  end
end
