require "test_helper"

# The rate is applied when a trip is completed (not later in a spreadsheet), and
# only bank-transfer categories touch a personal ledger.
class CompletionBillingRateTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    freeze_time
    BillingCategory.seed_defaults!
  end
  teardown { travel_back }

  def car(start_odometer: 1000)
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      c = Resource.create!(name: "VW", status: "active", resource_type: rt)
      c.resource_prices.create!(user_type: "resident", hour_rate: 10, day_rate: 0, km_rate: 2.5, min_charge: 0)
      c.create_resource_stat!(data: { "mileage" => start_odometer })
      c
    end
  end

  def person(name, key = nil)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident",
                 billing_category: key && BillingCategory.find_by(key: key))
  end

  def checked_in(user:, group: nil)
    Booking.create!(resource: car, user: user, destination: "Town", billing_group: group,
                    start_at: 2.hours.ago, end_at: 2.hours.from_now, status: "awaiting_return",
                    start_mileage: car.current_odometer, checked_in_at: 2.hours.ago)
  end

  test "an uncategorised trip is charged the plain amount and deducted" do
    user = person("Plain")
    booking = checked_in(user: user)

    ReservationCompletionService.call(booking: booking, ending_reading: 1040)

    assert_equal 120.0, booking.reload.total_amount.to_f  # 2h*10 + 40km*2.5
    assert_equal(-120.0, user.reload.account.balance.to_f, "bank transfer deducts")
  end

  test "a double-rate category charges twice and is invoiced, not deducted" do
    user = person("Perma", "perma")
    booking = checked_in(user: user)

    ReservationCompletionService.call(booking: booking, ending_reading: 1000) # 2h, 0 km

    assert_equal 40.0, booking.reload.total_amount.to_f, "20 base x2"
    assert_equal "multiplier", booking.billing_rate["mode"]
    assert_equal "20.0", booking.billing_rate["base"]
    assert_equal 0.0, user.reload.account.balance.to_f, "invoiced categories do not hit the ledger"
  end

  test "a group trip is charged the state rate and does not touch the driver's ledger" do
    driver = person("Driver")
    garden = BillingGroup.create!(name: "Garden", billing_category: BillingCategory.find_by!(key: "ks_arbejdsgruppe"))
    garden.billing_group_memberships.create!(user: driver)
    booking = checked_in(user: driver, group: garden)

    ReservationCompletionService.call(booking: booking, ending_reading: 1100) # 100 km

    assert_equal 394.0, booking.reload.total_amount.to_f, "100 km x 3,94"
    assert_equal 0.0, driver.reload.account.balance.to_f, "the group is billed, not the driver"
  end

  test "the receipt shows the applied rate and the charged total" do
    user = person("Perma", "perma")
    booking = checked_in(user: user)
    ReservationCompletionService.call(booking: booking, ending_reading: 1000)

    mail = ReceiptMailer.completion(booking.reload)
    body = mail.parts.map { |p| p.body.to_s }.join("\n")

    assert_match "Subtotal", body
    assert_match "20,00", body   # base
    assert_match "40,00", body   # charged total
    assert_match "perma", body
  end
end
