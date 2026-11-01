require "test_helper"

# The kørsel sheet splits a month into billing sections and applies each
# category's rule. Figures are taken from a real monthly sheet.
class MonthlyKoerselSheetTest < ActiveSupport::TestCase
  MONTH = "202606".freeze

  setup { BillingCategory.seed_defaults! }

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      Resource.create!(name: "VW", port: "E-46", status: "active", resource_type: rt)
    end
  end

  def bike
    @bike ||= begin
      rt = ResourceType.create!(name: "Bike-#{SecureRandom.hex(3)}", billing_type: "per_day", sort_order: 2)
      Resource.create!(name: "El-cykel", port: "A-02", status: "active", resource_type: rt)
    end
  end

  def person(name, key)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident",
                 billing_category: BillingCategory.find_by(key: key))
  end

  def group(name, key)
    BillingGroup.create!(name: name, billing_category: BillingCategory.find_by!(key: key))
  end

  # Mirrors what a real completion stores: the charged total plus the frozen rate,
  # with `amount` being the base before the rate is applied.
  def trip(user:, resource: car, amount:, km: 0, group: nil)
    b = Booking.new(resource: resource, user: user, destination: "Town", billing_group: group,
                    start_at: 3.hours.ago, end_at: 1.hour.ago, status: "returned",
                    completed_at: 2.hours.ago, billing_month: MONTH,
                    start_mileage: 1000, end_mileage: 1000 + km)
    b.save!(validate: false)
    rate = BillingRate.apply(category: b.effective_billing_category, base_total: amount, km: km)
    b.update_columns(total_amount: rate.charged, billing_rate: rate.for_storage)
    b
  end

  def sheet = MonthlyKoerselSheet.new(MONTH)

  test "people land in the section their category belongs to" do
    trip(user: person("Anne", "member"), amount: 3833.00, km: 1973)
    trip(user: person("Anders", "hp"),       amount: 3137.50, km: 1920)
    trip(user: person("Anna", "ansat_lejer"), amount: 121.00, km: 80)

    s = sheet
    assert_equal ["Anne"],   s.sections[1].map(&:label)
    assert_equal ["Anders"], s.sections[2].map(&:label)
    assert_equal ["Anna"],   s.sections[3].map(&:label)
  end

  test "section three shows the base and the doubled amount side by side" do
    trip(user: person("Anna", "ansat_lejer"), amount: 121.00, km: 80)

    row = sheet.sections[3].first
    assert_equal 121.00, row.biler.to_f,         "base stays as recorded"
    assert_equal 242.00, row.charged_biler.to_f, "charged is doubled"
  end

  test "work groups are charged the state rate on distance, not the normal amount" do
    garden = group("Garden", "ks_arbejdsgruppe")
    driver = person("Anna", "member")
    garden.billing_group_memberships.create!(user: driver)
    trip(user: driver, amount: 594.00, km: 510, group: garden)

    row = sheet.sections[4].first
    assert_equal "Garden", row.label, "billed to the group, not the driver"
    assert_equal 510, row.km
    assert_equal 2009.40, row.charged_biler.to_f, "510 km x 3,94"
  end

  test "a trip for a group is billed to the group even though a person drove" do
    choir = group("Choir", "interessegruppe")
    driver = person("Anna", "member")
    choir.billing_group_memberships.create!(user: driver)
    trip(user: driver, amount: 125.00, km: 80, group: choir)

    assert_empty sheet.sections[1].to_a, "must not also appear under the driver"
    assert_equal ["Choir"], sheet.sections[3].map(&:label)
    assert_equal 250.00, sheet.sections[3].first.charged_biler.to_f
  end

  test "bikes and cars are kept in separate columns" do
    someone = person("Sanne", "member")
    trip(user: someone, resource: bike, amount: 504.00)
    trip(user: someone, resource: car,  amount: 100.00, km: 50)

    row = sheet.sections[1].first
    assert_equal 504.00, row.cykler.to_f
    assert_equal 100.00, row.biler.to_f
  end

  test "grand totals reconcile against the plain recorded figures" do
    trip(user: person("Anne", "member"), amount: 1000.00, km: 100)
    trip(user: person("Anders", "hp"),       amount: 500.00,  km: 50)
    trip(user: person("Sanne", "member"), resource: bike, amount: 250.00)

    s = sheet
    assert_equal 1500.00, s.total_biler.to_f
    assert_equal 250.00,  s.total_cykler.to_f
  end

  test "trips by someone with no category still balance, and the gap is counted" do
    no_category = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                               name: "Ukendt", email: "#{SecureRandom.hex(5)}@example.com",
                               user_type: "resident")
    trip(user: no_category, amount: 200.00, km: 20)

    s = sheet
    assert_equal 1, s.uncategorised_count
    assert_equal 200.00, s.total_biler.to_f, "still included in the totals"
    assert_equal ["Ukendt"], s.sections[1].map(&:label), "falls back to Member"
  end

  test "renders a spreadsheet with the section headings" do
    trip(user: person("Anne", "member"), amount: 100.00, km: 10)
    xlsx = MonthlyKoerselXlsx.new(sheet).render
    assert xlsx.start_with?("PK"), "should be an xlsx"
    assert xlsx.bytesize > 3_000
  end
end
