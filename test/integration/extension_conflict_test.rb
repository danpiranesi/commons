require "test_helper"

# Extending a reservation looks forward: it may not run into the next booking on
# the same resource. The driver is told the latest time they can extend to.
class ExtensionConflictTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
  teardown { travel_back }

  def car
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    c = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    c.create_resource_stat!(data: { "mileage" => 1000 })
    c
  end

  def user
    @user ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                           name: "Dan", email: "d#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  test "extending into the next booking is refused with the latest allowed time" do
    c = car
    b = Booking.create!(resource: c, user: user, destination: "Town",
                        start_at: 2.hours.ago, end_at: 1.hour.from_now, status: "active", start_mileage: 1000)
    Booking.create!(resource: c, user: user, destination: "Later",
                    start_at: 3.hours.from_now, end_at: 5.hours.from_now, status: "active", start_mileage: 1000)

    post reservation_extension_path, params: { token: c.qr_token, booking_id: b.id,
                                               new_end: 4.hours.from_now.strftime("%Y-%m-%dT%H:%M") }
    assert_equal 1.hour.from_now.change(sec: 0), b.reload.end_at.change(sec: 0), "end time unchanged"
    follow_redirect!
    assert_match I18n.t("reservations.flash.extend_conflict", time: 3.hours.from_now.strftime("%-d/%-m %H:%M")), @response.body
  end

  test "extending right up to the next booking's start is allowed" do
    c = car
    b = Booking.create!(resource: c, user: user, destination: "Town",
                        start_at: 2.hours.ago, end_at: 1.hour.from_now, status: "active", start_mileage: 1000)
    Booking.create!(resource: c, user: user, destination: "Later",
                    start_at: 3.hours.from_now, end_at: 5.hours.from_now, status: "active", start_mileage: 1000)

    post reservation_extension_path, params: { token: c.qr_token, booking_id: b.id,
                                               new_end: 3.hours.from_now.strftime("%Y-%m-%dT%H:%M") }
    assert_equal 3.hours.from_now.change(sec: 0), b.reload.end_at.change(sec: 0)
  end
end
