require "test_helper"

# Cars and bicycles are reported apart so each fleet's income can be weighed
# against its costs. What hangs off a car — a trailer, a rocket box, a bridge
# crossing — is a car cost and lands in the car column.
class MonthlySheetSplitTest < ActiveSupport::TestCase
  MONTH = "209901".freeze

  setup do
    BillingCategory.seed_defaults!
    # The sheet is keyed only by billing month, so clear anything left in it.
    Booking.where(billing_month: MONTH).delete_all
    @user = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Bogholder",
                         email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident",
                         accounting_account: "1234", accounting_name: "Bogholder",
                         billing_category: BillingCategory.find_by(key: "member"))
  end

  def resource_of(name, billing_type:, hangs_off_a_car:)
    type = ResourceType.create!(name: "#{name}-#{SecureRandom.hex(3)}", billing_type: billing_type,
                                sort_order: 1, inherit_rules_from_car: hangs_off_a_car)
    Resource.create!(name: "#{name}-#{SecureRandom.hex(3)}", status: "active", resource_type: type)
  end

  def bill(resource, amount)
    Booking.create!(resource: resource, user: @user, destination: "T", status: "returned",
                    start_at: 3.hours.ago, end_at: 1.hour.ago, completed_at: 1.hour.ago,
                    total_amount: amount, billing_month: MONTH,
                    billing_rate: { "mode" => "normal", "value" => "1.0", "category" => "Medlem",
                                    "base" => amount.to_s, "km" => 0, "charged" => amount.to_s })
  end

  def sheet = MonthlyKoerselSheet.new(MONTH)

  test "a car counts as a car" do
    bill(resource_of("Car", billing_type: "per_day_and_km", hangs_off_a_car: false), 100)
    assert_equal 100, sheet.total_biler.to_f
    assert_equal 0, sheet.total_cykler.to_f
  end

  test "a bicycle counts as a bicycle" do
    bill(resource_of("Bicycle", billing_type: "per_day", hangs_off_a_car: false), 40)
    assert_equal 40, sheet.total_cykler.to_f
    assert_equal 0, sheet.total_biler.to_f
  end

  test "a trailer is a car cost, not a bicycle cost" do
    bill(resource_of("Trailer", billing_type: "per_day", hangs_off_a_car: true), 60)
    assert_equal 60, sheet.total_biler.to_f, "a trailer is towed by a car"
    assert_equal 0, sheet.total_cykler.to_f
  end

  test "a rocket box and a bridge toll are car costs too" do
    bill(resource_of("Rocket Box", billing_type: "per_day", hangs_off_a_car: true), 25)
    bill(resource_of("Toll", billing_type: "per_day", hangs_off_a_car: true), 250)
    assert_equal 275, sheet.total_biler.to_f
    assert_equal 0, sheet.total_cykler.to_f
  end

  test "the bank-transfer sheets split the same way" do
    bill(resource_of("Car", billing_type: "per_day_and_km", hangs_off_a_car: false), 100)
    bill(resource_of("Trailer", billing_type: "per_day", hangs_off_a_car: true), 60)
    bill(resource_of("Bicycle", billing_type: "per_day", hangs_off_a_car: false), 40)

    assert_equal 160, sheet.bank_total_for("bil").to_f, "car sheet carries the trailer too"
    assert_equal 40,  sheet.bank_total_for("cykel").to_f
    assert_equal 200, sheet.bank_total.to_f, "and the two still add up to everything"
  end

  test "the export names the same three worksheets" do
    bill(resource_of("Car", billing_type: "per_day_and_km", hangs_off_a_car: false), 100)
    xlsx = MonthlyKoerselXlsx.new(sheet).render

    require "zip"
    names = nil
    # open_buffer returns the buffer, not the block's value, so collect outside.
    Zip::File.open_buffer(xlsx) do |zip|
      xml = zip.find_entry("xl/workbook.xml").get_input_stream.read.force_encoding("UTF-8")
      names = xml.scan(/<sheet[^>]*name="([^"]+)"/).flatten
    end
    assert_equal ["Kørsel", "Biler jan", "Cykler jan"], names
  end
end
