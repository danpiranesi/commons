require "test_helper"

# A resource with no price of its own inherits its type's default hourly rate.
class DefaultHourRateTest < ActiveSupport::TestCase
  def car_type
    @car_type ||= ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
  end

  test "seeding sets 5 kr/hour for every user type on priceable types" do
    car_type
    ResourceType.seed_default_rates!
    assert_equal 5.0, car_type.reload.default_hour_rate_for("resident").to_f
    assert_equal 5.0, car_type.default_hour_rate_for("employee").to_f
  end

  test "tolls get no default hourly rate" do
    toll = ResourceType.create!(name: "Toll", billing_type: "free", sort_order: 9)
    ResourceType.seed_default_rates!
    assert_nil toll.reload.default_hour_rate_for("resident")
  end

  test "a resource with no price inherits the type default" do
    car_type.update!(default_hour_rates: { "resident" => "5.0", "employee" => "5.0" })
    car = Resource.create!(name: "Unpriced", status: "active", resource_type: car_type)

    assert_equal 5.0, car.price_for("resident").hour_rate.to_f
    assert_equal 5.0, car.price_for("employee").hour_rate.to_f, "the default is not doubled for employees"
  end

  test "a resource with its own price ignores the default" do
    car_type.update!(default_hour_rates: { "resident" => "5.0" })
    car = Resource.create!(name: "Priced", status: "active", resource_type: car_type)
    car.resource_prices.create!(user_type: "resident", hour_rate: 12, day_rate: 0, km_rate: 2.5, min_charge: 0)

    assert_equal 12.0, car.price_for("resident").hour_rate.to_f
    assert_equal 24.0, car.price_for("employee").hour_rate.to_f, "explicit prices keep the employee doubling"
  end

  test "seeding never overwrites a default an admin changed" do
    car_type.update!(default_hour_rates: { "resident" => "8.5" })
    ResourceType.seed_default_rates!
    assert_equal 8.5, car_type.reload.default_hour_rate_for("resident").to_f
    assert_equal 5.0, car_type.default_hour_rate_for("employee").to_f, "the missing one is filled in"
  end
end
