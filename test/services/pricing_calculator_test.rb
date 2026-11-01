require "test_helper"

class PricingCalculatorTest < ActiveSupport::TestCase
  def make_user
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                 name: "T", email: "u#{SecureRandom.hex(6)}@example.com", user_type: "resident")
  end

  def car_with_price(hour_rate: 10, km_rate: 2.5)
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    car = Resource.create!(name: "C-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    car.resource_prices.create!(user_type: "resident", hour_rate: hour_rate, day_rate: 0,
                                km_rate: km_rate, min_charge: 0)
    car
  end

  def booking_for(resource, user, hours: 2)
    start_at = Time.current.change(usec: 0)
    Booking.create!(resource: resource, user: user, start_at: start_at, end_at: start_at + hours.hours,
                    status: "active", destination: resource.tracks_mileage? ? "x" : nil)
  end

  test "per_day_and_km breakdown = time + km, total sums correctly" do
    user = make_user
    car = car_with_price
    b = booking_for(car, user, hours: 2)

    bd = PricingCalculator.new(b, start_odometer: 1000, ending_reading: 1200).breakdown
    assert_equal 20.0, bd.time_cost.to_f          # 2h * 10
    assert_equal 500.0, bd.km_cost.to_f           # 200km * 2.5
    assert_equal 0.0, bd.toll_cost.to_f
    assert_equal 0.0, bd.accessory_cost.to_f
    assert_equal 520.0, bd.total.to_f
  end

  test "no km cost when reading not provided" do
    user = make_user
    car = car_with_price
    b = booking_for(car, user)
    bd = PricingCalculator.new(b).breakdown
    assert_equal 0.0, bd.km_cost.to_f
    assert_equal 20.0, bd.total.to_f
  end

  test "per_day resource has time cost but never km cost" do
    user = make_user
    rt = ResourceType.create!(name: "Bike-#{SecureRandom.hex(3)}", billing_type: "per_day", sort_order: 2)
    bike = Resource.create!(name: "B-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    bike.resource_prices.create!(user_type: "resident", hour_rate: 8, day_rate: 0, km_rate: 0, min_charge: 0)
    b = booking_for(bike, user, hours: 3)

    bd = PricingCalculator.new(b, start_odometer: 1000, ending_reading: 9999).breakdown
    assert_equal 24.0, bd.time_cost.to_f  # 3h * 8
    assert_equal 0.0, bd.km_cost.to_f     # ignored for per_day
  end

  test "free resource costs nothing for time" do
    user = make_user
    rt = ResourceType.create!(name: "Free-#{SecureRandom.hex(3)}", billing_type: "free", sort_order: 3)
    room = Resource.create!(name: "R-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    b = booking_for(room, user, hours: 5)

    bd = PricingCalculator.new(b).breakdown
    assert_equal 0.0, bd.total.to_f
  end

  # ── Car minimum price (time + km combined, floored) ──────────────────

  test "a car reservation below the minimum is rounded up to it" do
    user = make_user
    car = car_with_price # 10/hr, 2.5/km
    b = booking_for(car, user, hours: 1) # time = 10

    # 2 km × 2.5 = 5, so driving = 15, below the 20 minimum.
    bd = PricingCalculator.new(b, start_odometer: 1000, ending_reading: 1002).breakdown
    assert_equal 20.0, bd.total.to_f, "floored to the 20 kr minimum"
    assert_equal 15.0, bd.time_cost.to_f, "the 5 kr top-up folds into time_cost"
    assert_equal 5.0, bd.km_cost.to_f, "km line unchanged"
  end

  test "a car reservation at or above the minimum pays the actual total" do
    user = make_user
    car = car_with_price
    b = booking_for(car, user, hours: 2) # time = 20

    bd = PricingCalculator.new(b, start_odometer: 1000, ending_reading: 1040).breakdown # 40km × 2.5 = 100
    assert_equal 120.0, bd.total.to_f, "no flooring once it clears the minimum"
    assert_equal 20.0, bd.time_cost.to_f
  end

  test "the minimum is the setting value, and adjustable" do
    SiteSetting.instance.update!(car_minimum_price: 35)
    user = make_user
    car = car_with_price
    b = booking_for(car, user, hours: 1) # time 10

    bd = PricingCalculator.new(b, start_odometer: 1000, ending_reading: 1000).breakdown
    assert_equal 35.0, bd.total.to_f
  end

  test "home cars use the lower home minimum" do
    user = make_user
    car = car_with_price
    car.update!(home_car: true)
    b = booking_for(car, user, hours: 1) # time 10, no km

    bd = PricingCalculator.new(b, start_odometer: 1000, ending_reading: 1000).breakdown
    assert_equal 10.0, bd.total.to_f, "home-car minimum is 10, not 20"
  end

  test "the car minimum does not apply to bikes" do
    user = make_user
    rt = ResourceType.create!(name: "Bike-#{SecureRandom.hex(3)}", billing_type: "per_day", sort_order: 2)
    bike = Resource.create!(name: "B-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    bike.resource_prices.create!(user_type: "resident", hour_rate: 2, day_rate: 0, km_rate: 0, min_charge: 0)
    b = booking_for(bike, user, hours: 1) # 2 kr, well under 20

    bd = PricingCalculator.new(b).breakdown
    assert_equal 2.0, bd.total.to_f, "bikes are not floored by the car minimum"
  end

  test "tolls sit on top of the minimum, not inside it" do
    user = make_user
    car = car_with_price
    b = booking_for(car, user, hours: 1) # time 10, no km → driving 10, floored to 20
    toll_rt = ResourceType.create!(name: "Toll", billing_type: "free", sort_order: 9)
    toll = Resource.create!(name: "Bridge-#{SecureRandom.hex(3)}", status: "active", resource_type: toll_rt)
    toll.resource_prices.create!(user_type: "resident", hour_rate: 100, day_rate: 0, km_rate: 0, min_charge: 0)
    b.booking_accessories.create!(accessory: toll, quantity: 1)

    bd = PricingCalculator.new(b, start_odometer: 1000, ending_reading: 1000).breakdown
    assert_equal 100.0, bd.toll_cost.to_f
    assert_equal 120.0, bd.total.to_f, "20 minimum driving + 100 toll"
  end
end
