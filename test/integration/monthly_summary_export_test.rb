require "test_helper"
require "zip"

# The monthly overview exports the kørsel sheet: one block per billing category,
# with the double rate and the state rate applied on top of the plain figures.
class MonthlySummaryExportTest < ActionDispatch::IntegrationTest
  BILLING_MONTH = "202606".freeze

  setup { BillingCategory.seed_defaults! }

  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      Resource.create!(name: "VW", port: "E-46", status: "active", resource_type: rt)
    end
  end

  def person(name, key)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident",
                 billing_category: BillingCategory.find_by(key: key))
  end

  def trip(user:, amount:, km: 0, group: nil)
    b = Booking.new(resource: car, user: user, destination: "Town", billing_group: group,
                    start_at: 3.hours.ago, end_at: 1.hour.ago, status: "returned",
                    completed_at: 2.hours.ago, billing_month: BILLING_MONTH,
                    start_mileage: 1000, end_mileage: 1000 + km)
    b.save!(validate: false)
    rate = BillingRate.apply(category: b.effective_billing_category, base_total: amount, km: km)
    b.update_columns(total_amount: rate.charged, billing_rate: rate.for_storage)
    b
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  def sheet_text
    get export_summary_admin_monthly_overview_path(billing_month: BILLING_MONTH)
    text = +""
    Zip::File.open_buffer(@response.body) do |zip|
      zip.each do |entry|
        next unless entry.name.end_with?(".xml")
        text << entry.get_input_stream.read.force_encoding("UTF-8")
      end
    end
    text
  end

  test "downloads a spreadsheet with a block per category" do
    trip(user: person("Anne", "member"), amount: 3833.00, km: 1973)
    trip(user: person("Anders", "hp"), amount: 3137.50, km: 1920)
    trip(user: person("Anna", "ansat_lejer"), amount: 121.00, km: 80)
    sign_in(admin)

    text = sheet_text

    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", @response.media_type
    assert_match "koersel_202606.xlsx", @response.headers["Content-Disposition"]

    assert_match "Kørsel juni 2026", text
    assert_match "Medlemmer i fælles økonomi", text
    assert_match "HP-ordninger", text
    assert_match "dobbelt takst", text
    assert_match "statens takst", text

    assert_match "Anne", text
    assert_match "Anders", text
    # base and doubled both present for the double-rate block
    assert_match "121", text
    assert_match "242", text
  end

  test "the sheet is produced even when nothing has been categorised" do
    BillingCategory.delete_all
    uncategorised = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                                 name: "Ukendt", email: "#{SecureRandom.hex(5)}@example.com",
                                 user_type: "resident")
    trip(user: uncategorised, amount: 200.00, km: 20)
    sign_in(admin)

    get export_summary_admin_monthly_overview_path(billing_month: BILLING_MONTH)

    assert_response :success, "a missing category must not break the export"
    assert @response.body.start_with?("PK")
  end

  test "non-admins cannot download it" do
    sign_in(person("Someone", "member"))
    get export_summary_admin_monthly_overview_path(billing_month: BILLING_MONTH)
    assert_redirected_to root_path
  end
end
