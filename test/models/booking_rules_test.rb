require "test_helper"

class BookingRulesTest < ActiveSupport::TestCase
  def type(rules = {})
    ResourceType.new(name: "Car", billing_type: "per_day_and_km", booking_rules: rules)
  end

  test "defaults give a generous scan window when nothing is stored" do
    r = BookingRules.for(type)
    assert_equal 30, r.checkout_buffer_minutes
    assert_equal 60, r.return_buffer_minutes
    assert r.require_odometer?
    assert r.allow_extension?
    assert r.require_confirmation?
    assert_equal 2000, r.max_km_per_trip
  end

  test "stored values override defaults, per stage" do
    r = BookingRules.for(type(
      "checkout" => { "buffer_minutes" => 30 },
      "checkin"  => { "buffer_minutes" => 10, "require_confirmation" => false }
    ))
    assert_equal 30, r.checkout_buffer_minutes
    assert_equal 10, r.return_buffer_minutes
    assert_not r.require_confirmation?
    assert r.require_odometer?, "unset keys keep their default"
  end

  test "boolean rules cast from checkbox-style strings" do
    assert_not BookingRules.for(type("checkout" => { "require_odometer" => "0" })).require_odometer?
    assert BookingRules.for(type("during" => { "allow_extension" => "1" })).allow_extension?
  end

  test "nil resource type falls back to all defaults" do
    r = BookingRules.for(nil)
    assert r.require_odometer?
    assert_equal 2000, r.max_km_per_trip
  end
end
