require "test_helper"

# Trailers, rocket boxes and tolls inherit the car's lifecycle rules rather than
# carrying their own.
class RulesInheritanceTest < ActiveSupport::TestCase
  def car
    @car ||= ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1,
                                  booking_rules: { "checkout" => { "buffer_minutes" => 25 },
                                                   "checkin" => { "overdue_after_minutes" => 15 } })
  end

  test "a type marked to inherit uses the car's rules" do
    car
    trailer = ResourceType.create!(name: "Trailer", billing_type: "per_day", sort_order: 3,
                                   inherit_rules_from_car: true)
    rules = BookingRules.for(trailer)
    assert_equal 25, rules.checkout_buffer_minutes, "inherits the car's checkout buffer"
    assert_equal 15, rules.overdue_after_minutes
  end

  test "a type with its own rules is unaffected" do
    car
    bike = ResourceType.create!(name: "Bicycle", billing_type: "per_day", sort_order: 2,
                                booking_rules: { "checkout" => { "buffer_minutes" => 5 } })
    assert_equal 5, BookingRules.for(bike).checkout_buffer_minutes
  end

  test "the car itself never recurses even if the flag is set" do
    c = car
    c.update!(inherit_rules_from_car: true)
    assert_equal 25, BookingRules.for(c).checkout_buffer_minutes
  end

  test "inheriting types are excluded from with_own_rules" do
    car
    ResourceType.create!(name: "Toll", billing_type: "per_day", sort_order: 5, inherit_rules_from_car: true)
    names = ResourceType.with_own_rules.pluck(:name)
    assert_includes names, "Car"
    refute_includes names, "Toll"
  end
end
