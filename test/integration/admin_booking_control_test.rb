require "test_helper"

# An admin is the one who untangles a mess, so a booking must not become
# untouchable the moment somebody scans it out. Members keep the narrower rule:
# they can only change a trip they have not started.
class AdminBookingControlTest < ActionDispatch::IntegrationTest
  setup do
    @admin  = member("Anna", admin: true)
    @driver = member("Bjørn")
    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    @car = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    @car.create_resource_stat!(data: { "mileage" => 1000 })
  end

  def member(name, admin: false)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{SecureRandom.hex(4)}@example.com", user_type: "resident", admin: admin)
  end

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  def checked_out_booking
    Booking.create!(resource: @car, user: @driver, destination: "Town",
                    start_at: 3.hours.ago, end_at: 1.hour.ago, status: "awaiting_return",
                    checked_in_at: 3.hours.ago, start_mileage: 1000)
  end

  test "an admin can cancel a booking that is already checked out" do
    b = checked_out_booking
    sign_in @admin
    patch cancel_booking_path(b), params: { reason: "Duplicate" }
    assert_equal "cancelled", b.reload.status
  end

  test "a member cannot cancel their own trip once it is checked out" do
    b = checked_out_booking
    sign_in @driver
    patch cancel_booking_path(b)
    assert_equal "awaiting_return", b.reload.status
  end

  test "an admin can open the edit form for a checked-out booking" do
    b = checked_out_booking
    sign_in @admin
    get edit_booking_path(b)
    assert_response :success
  end

  test "a member is turned away from editing a checked-out booking" do
    b = checked_out_booking
    sign_in @driver
    get edit_booking_path(b)
    assert_redirected_to booking_path(b)
  end

  test "an admin can delete a booking that has not been billed" do
    b = checked_out_booking
    sign_in @admin
    assert_difference -> { Booking.count }, -1 do
      delete booking_path(b)
    end
  end

  test "a booking with a charge against it cannot be deleted" do
    b = Booking.create!(resource: @car, user: @driver, destination: "Town",
                        start_at: 3.hours.ago, end_at: 1.hour.ago, status: "returned",
                        completed_at: 1.hour.ago, start_mileage: 1000, end_mileage: 1020,
                        total_amount: 25)
    Transaction.create!(account: @driver.account, user: @driver, booking: b,
                        amount: -25, description: "Trip")
    sign_in @admin
    assert_no_difference -> { Booking.count } do
      delete booking_path(b)
    end
  end

  test "a member cannot delete a booking at all" do
    b = checked_out_booking
    sign_in @driver
    assert_no_difference -> { Booking.count } do
      delete booking_path(b)
    end
  end

  # Moving a trip into a signed-off month would change a sheet the bookkeeper
  # has already closed.
  test "a booking cannot be moved into a closed billing month" do
    trip = Booking.create!(resource: @car, user: @driver, destination: "Town",
                           start_at: 3.hours.ago, end_at: 1.hour.ago, status: "returned",
                           completed_at: 1.hour.ago, start_mileage: 1000, end_mileage: 1020,
                           total_amount: 25, billing_month: Time.current.strftime("%Y%m"))
    closed = 1.month.ago.strftime("%Y%m")
    ClosedBillingMonth.create!(billing_month: closed)

    sign_in @admin
    patch admin_booking_path(trip), params: { booking: { billing_month: closed } }

    assert_response :unprocessable_entity
    assert_equal Time.current.strftime("%Y%m"), trip.reload.billing_month
  end

  test "deleting is refused, not crashed, when an accessory on the trip was billed" do
    trailer_type = ResourceType.create!(name: "Trailer-#{SecureRandom.hex(3)}",
                                        billing_type: "per_day", sort_order: 2)
    trailer = Resource.create!(name: "T-#{SecureRandom.hex(3)}", status: "active",
                               resource_type: trailer_type)
    parent = checked_out_booking
    shadow = parent.accessory_bookings.create!(user: @driver, resource: trailer,
                                               start_at: parent.start_at, end_at: parent.end_at,
                                               status: "returned", completed_at: 1.hour.ago,
                                               total_amount: 15)
    Transaction.create!(account: @driver.account, user: @driver, booking: shadow,
                        amount: -15, description: "Trailer")

    sign_in @admin
    assert_no_difference -> { Booking.count } do
      delete booking_path(parent)
    end
    assert_redirected_to booking_path(parent)
  end
end
