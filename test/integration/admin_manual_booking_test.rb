require "test_helper"

# An admin books on behalf of another member: the booking goes to the target
# user, a non-admin's target_user_id is ignored, and the user search endpoint.
class AdminManualBookingTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 7, 15, 10, 0, 0)

    @admin = User.create!(
      discourse_id: SecureRandom.random_number(1_000_000_000),
      name: "Anna Admin", email: "anna_admin@example.com",
      user_type: "resident", admin: true
    )
    @member = User.create!(
      discourse_id: SecureRandom.random_number(1_000_000_000),
      name: "Erik Member", email: "erik@example.com",
      user_type: "resident", initials: "Erik Me", housing_unit: "North Wing"
    )

    @rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    @resource = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: @rt)
    @resource.create_resource_stat!(data: { "mileage" => 10_000 })
    @resource.resource_prices.create!(user_type: "resident", hour_rate: 5, day_rate: 80, km_rate: 2, min_charge: 0)

    @period = BookingPeriod.create!(
      name: "July 2026", status: "open",
      start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 7, 31)
    )
  end

  teardown { travel_back }

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  # --- User search endpoint ---

  test "search returns matching users as JSON" do
    sign_in @admin
    get search_admin_users_path, params: { q: "erik" }, as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data.size
    assert_equal @member.id, data.first["id"]
    assert_equal "Erik Member", data.first["name"]
    assert_equal "Erik Me", data.first["initials"]
    assert_equal "North Wing", data.first["housing_unit"]
  end

  test "search requires at least 2 characters" do
    sign_in @admin
    get search_admin_users_path, params: { q: "e" }, as: :json
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  test "search also matches on initials and housing_unit" do
    sign_in @admin
    get search_admin_users_path, params: { q: "North" }, as: :json
    data = JSON.parse(response.body)
    assert data.any? { |u| u["id"] == @member.id }
  end

  test "non-admin cannot access search" do
    sign_in @member
    get search_admin_users_path, params: { q: "anna" }, as: :json
    assert_response :redirect
  end

  # --- Admin books for another member ---

  test "admin can create a booking assigned to another member" do
    sign_in @admin
    assert_difference -> { @member.bookings.count }, 1 do
      post bookings_path, params: {
        target_user_id: @member.id,
        booking: {
          resource_id: @resource.id,
          start_at:    "2026-07-16 09:00",
          end_at:      "2026-07-16 17:00",
          destination: "Town",
          rideshare_available: "1"
        }
      }
    end
    assert_response :redirect
    booking = @member.bookings.last
    assert_equal @member, booking.user
    assert_equal @resource, booking.resource
  end

  test "booking is not assigned to the admin" do
    sign_in @admin
    post bookings_path, params: {
      target_user_id: @member.id,
      booking: {
        resource_id: @resource.id,
        start_at:    "2026-07-16 09:00",
        end_at:      "2026-07-16 17:00",
        destination: "Town"
      }
    }
    assert_equal 0, @admin.bookings.count
  end

  test "non-admin target_user_id is silently ignored — booking goes to self" do
    sign_in @member
    post bookings_path, params: {
      target_user_id: @admin.id,   # attempt to book as admin
      booking: {
        resource_id: @resource.id,
        start_at:    "2026-07-16 09:00",
        end_at:      "2026-07-16 17:00",
        destination: "Town"
      }
    }
    assert_response :redirect
    assert_equal 1, @member.bookings.count
    assert_equal @member, @member.bookings.last.user
    assert_equal 0, @admin.bookings.count
  end

  # --- Admin user edit ---

  test "admin can update member accounting fields" do
    sign_in @admin
    patch admin_user_path(@member), params: {
      user: { accounting_account: "4210", accounting_name: "Erik M.", phone: "26123456" }
    }
    assert_redirected_to admin_users_path
    @member.reload
    assert_equal "4210", @member.accounting_account
    assert_equal "Erik M.", @member.accounting_name
    assert_equal "26123456", @member.phone
  end

  test "non-admin cannot edit users" do
    sign_in @member
    patch admin_user_path(@admin), params: { user: { accounting_account: "9999" } }
    assert_response :redirect
    assert_nil @admin.reload.accounting_account
  end
end
