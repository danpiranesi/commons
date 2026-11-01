require "test_helper"

# The booking form refuses a start in the past; admins may still backdate.
class BookingBackdatingTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup { travel_to Time.zone.local(2026, 10, 5, 10, 12) }
  teardown { travel_back }

  def bike
    @bike ||= begin
      rt = ResourceType.create!(name: "Bike-#{SecureRandom.hex(3)}", billing_type: "per_day", sort_order: 2)
      Resource.create!(name: "B-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    end
  end

  def member
    @member ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                             name: "Mia", email: "m#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  def form_booking(start_at:, admin: false)
    Booking.new(resource: bike, user: member, start_at: start_at, end_at: start_at + 2.hours,
                status: "active").tap do |b|
      b.from_booking_form = true
      b.creating_admin = admin
    end
  end

  test "a member cannot book yesterday" do
    b = form_booking(start_at: 1.day.ago)
    refute b.valid?
    assert b.errors.of_kind?(:start_at, :in_the_past)
  end

  test "the half-hour slot already under way can still be booked" do
    assert form_booking(start_at: Time.zone.local(2026, 10, 5, 10, 0)).valid?
  end

  test "admins may backdate" do
    assert form_booking(start_at: 1.day.ago, admin: true).valid?
  end

  test "editing the end of a trip already under way is allowed" do
    b = Booking.create!(resource: bike, user: member, start_at: 3.hours.ago, end_at: 1.hour.from_now,
                        status: "active")
    b.from_booking_form = true
    b.end_at = 2.hours.from_now
    assert b.valid?
  end

  test "moving a start into the past on edit is refused" do
    b = Booking.create!(resource: bike, user: member, start_at: 1.day.from_now, end_at: 1.day.from_now + 2.hours,
                        status: "active")
    b.from_booking_form = true
    b.start_at = 1.day.ago
    refute b.valid?
  end
end
