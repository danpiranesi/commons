require "test_helper"

# Members can only book within the booking horizon (SiteSetting.booking_horizon_days).
# Admins are exempt; 0 means unlimited.
class BookingHorizonTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup { freeze_time }
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

  def build_booking(start_at:, creating_admin: false)
    Booking.new(resource: bike, user: member, start_at: start_at, end_at: start_at + 2.hours,
                status: "active").tap { |b| b.creating_admin = creating_admin }
  end

  test "a booking within the horizon is valid" do
    SiteSetting.instance.update!(booking_horizon_days: 45)
    assert build_booking(start_at: 30.days.from_now).valid?
  end

  test "a booking beyond the horizon is rejected for members" do
    SiteSetting.instance.update!(booking_horizon_days: 45)
    b = build_booking(start_at: 60.days.from_now)
    refute b.valid?
    assert b.errors.of_kind?(:start_at, :beyond_horizon)
  end

  test "admins bypass the horizon" do
    SiteSetting.instance.update!(booking_horizon_days: 45)
    assert build_booking(start_at: 60.days.from_now, creating_admin: true).valid?
  end

  test "a horizon of 0 means unlimited" do
    SiteSetting.instance.update!(booking_horizon_days: 0)
    assert build_booking(start_at: 2.years.from_now).valid?
  end

  test "the boundary day itself is bookable" do
    SiteSetting.instance.update!(booking_horizon_days: 45)
    # 45 days ahead, early in the day, is within; the horizon is inclusive of the date.
    assert build_booking(start_at: (Date.current + 45).to_time.change(hour: 9)).valid?
    refute build_booking(start_at: (Date.current + 46).to_time.change(hour: 9)).valid?
  end

  test "within_booking_horizon? helper respects the setting" do
    ss = SiteSetting.instance
    ss.update!(booking_horizon_days: 10)
    assert ss.within_booking_horizon?(Date.current + 10)
    refute ss.within_booking_horizon?(Date.current + 11)
    ss.update!(booking_horizon_days: 0)
    assert ss.within_booking_horizon?(Date.current + 1000)
  end

  # ── Settings save ──────────────────────────────────────────────
  test "the horizon is saved from the settings page" do
    admin = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                         name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                         user_type: "resident", admin: true)
    get "/test/sign_in/#{admin.id}"

    patch admin_homepage_header_path, params: {
      site_setting: { car_minimum_price: "20", home_car_minimum_price: "10", booking_horizon_days: "30" }
    }
    assert_equal 30, SiteSetting.instance.booking_horizon_days
  end
end
