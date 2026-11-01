require "test_helper"

class ReservationCheckInServiceTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def make_user(name: "Driver")
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                 name: name, email: "u#{SecureRandom.hex(6)}@example.com", user_type: "resident")
  end

  def make_car(start_odometer: 1000)
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    car = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    car.resource_prices.create!(user_type: "resident", hour_rate: 10, day_rate: 0, km_rate: 2.5, min_charge: 0)
    car.create_resource_stat!(data: { "mileage" => start_odometer })
    car
  end

  def make_booking(car:, user:, status: "active", start_at: 1.hour.ago, end_at: 2.hours.from_now)
    Booking.create!(resource: car, user: user, start_at: start_at, end_at: end_at,
                    status: status, destination: "Town")
  end

  test "check-in records the start reading, flips to awaiting_return, reconciles the odometer" do
    car = make_car(start_odometer: 1000)
    booking = make_booking(car: car, user: make_user)

    result = ReservationCheckInService.call(booking: booking, starting_reading: 1005)

    assert result.success?, result.error.inspect
    booking.reload
    assert_equal "awaiting_return", booking.status
    assert_equal 1005, booking.start_mileage
    assert booking.checked_in?
    assert_equal 1005, car.reload.current_odometer
  end

  test "a starting reading below the last odometer is rejected" do
    car = make_car(start_odometer: 1000)
    booking = make_booking(car: car, user: make_user)

    result = ReservationCheckInService.call(booking: booking, starting_reading: 900)

    assert result.failure?
    assert_equal :reading_too_low, result.error
    assert_equal "active", booking.reload.status
  end

  test "checking in auto-closes a previous driver's forgotten booking at this reading" do
    car = make_car(start_odometer: 1000)
    forgetful = make_user(name: "Forgetful")
    # Previous booking, never ended, still active from earlier today.
    stale = make_booking(car: car, user: forgetful, status: "active",
                         start_at: 5.hours.ago, end_at: 3.hours.ago)

    newcomer = make_user(name: "Newcomer")
    current = make_booking(car: car, user: newcomer, start_at: 1.hour.ago, end_at: 2.hours.from_now)

    result = nil
    assert_difference -> { Transaction.count }, 1 do # the forgotten booking gets charged
      result = ReservationCheckInService.call(booking: current, starting_reading: 1200)
    end

    assert result.success?
    assert_equal "returned", stale.reload.status
    assert_equal 1200, stale.end_mileage, "forgotten trip closed at the new driver's reading"
    assert_equal "awaiting_return", current.reload.status
    assert_equal 1200, current.start_mileage
    assert_equal 1200, car.reload.current_odometer
  end

  test "check-in is not applicable to non-mileage resources" do
    rt = ResourceType.create!(name: "Bike-#{SecureRandom.hex(3)}", billing_type: "free", sort_order: 2)
    bike = Resource.create!(name: "Bike", status: "active", resource_type: rt)
    booking = Booking.create!(resource: bike, user: make_user, start_at: 1.hour.ago, end_at: 1.hour.from_now, status: "active")

    result = ReservationCheckInService.call(booking: booking, starting_reading: 5)
    assert result.failure?
    assert_equal :not_applicable, result.error
  end

  test "an already checked-in booking cannot be checked in again" do
    car = make_car
    booking = make_booking(car: car, user: make_user, status: "awaiting_return")
    booking.update!(checked_in_at: Time.current, start_mileage: 1000)

    result = ReservationCheckInService.call(booking: booking, starting_reading: 1010)
    assert result.failure?
    assert_equal :already_checked_in, result.error
  end
end
