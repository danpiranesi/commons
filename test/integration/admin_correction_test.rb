require "test_helper"

# Admin corrections to a completed reservation: mileage (offsets the ledger,
# updates the odometer when latest), billing month, and access control.
class AdminCorrectionTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 7, 15, 12, 0, 0)

    @admin = User.create!(
      discourse_id: SecureRandom.random_number(1_000_000_000),
      name: "Anna Admin", email: "anna@example.com",
      user_type: "resident", admin: true
    )
    @member = User.create!(
      discourse_id: SecureRandom.random_number(1_000_000_000),
      name: "Erik", email: "erik@example.com",
      user_type: "resident"
    )

    @rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    @resource = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: @rt)
    @resource.create_resource_stat!(data: { "mileage" => 50_000 })

    rp = @resource.resource_prices.build(user_type: "resident", hour_rate: 5, day_rate: 80, km_rate: 2, min_charge: 0)
    rp.save!

    @account = @member.account

    @booking = Booking.create!(
      resource: @resource, user: @member,
      destination: "Town",
      start_at: Time.zone.local(2026, 7, 14, 9, 0),
      end_at:   Time.zone.local(2026, 7, 14, 17, 0),
      status: "returned",
      completed_at: Time.zone.local(2026, 7, 14, 16, 0),
      start_mileage: 50_000,
      end_mileage:   50_100,
      total_amount:  300.00,
      billing_month: "202607"
    )
    # Ledger matches total_amount so the correction delta is consistent
    @account.transactions.create!(
      user: @member, booking: @booking,
      amount: -300.00, description: "original charge"
    )
  end

  teardown { travel_back }

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  # --- Access control ---

  test "non-admin cannot access correction page" do
    sign_in @member
    get edit_admin_booking_path(@booking)
    assert_response :redirect
  end

  # --- Edit page loads ---

  test "admin sees correction form for a returned booking" do
    sign_in @admin
    get edit_admin_booking_path(@booking)
    assert_response :success
    assert_match @booking.resource.display_name, response.body
    assert_match @member.name, response.body
  end

  # --- Mileage correction ---

  test "correcting end_mileage reposts an offsetting transaction" do
    sign_in @admin
    assert_difference -> { @account.transactions.reload.count }, 1 do
      patch admin_booking_path(@booking), params: { booking: { end_mileage: 50_200, billing_month: "202607" } }
    end
    assert_redirected_to edit_admin_booking_path(@booking)
    follow_redirect!
    assert_match I18n.t("admin.bookings.notices.mileage_corrected"), response.body

    @booking.reload
    assert_equal 50_200, @booking.end_mileage
    assert @booking.total_amount > 300.00   # more km → higher charge
  end

  test "correcting end_mileage updates the resource odometer (latest booking)" do
    sign_in @admin
    patch admin_booking_path(@booking), params: { booking: { end_mileage: 50_200, billing_month: "202607" } }
    assert_equal 50_200, @resource.reload.current_odometer
  end

  test "reading lower than start_mileage is rejected" do
    sign_in @admin
    patch admin_booking_path(@booking), params: { booking: { end_mileage: 40_000, billing_month: "202607" } }
    assert_response :unprocessable_entity
    @booking.reload
    assert_equal 50_100, @booking.end_mileage  # unchanged
  end

  # --- Billing month ---

  test "changing billing_month only does not post an offsetting transaction" do
    sign_in @admin
    assert_no_difference -> { @account.transactions.reload.count } do
      patch admin_booking_path(@booking), params: { booking: { end_mileage: 50_100, billing_month: "202606" } }
    end
    assert_redirected_to edit_admin_booking_path(@booking)
    assert_equal "202606", @booking.reload.billing_month
  end

  test "billing_month is set automatically on completion" do
    resource2 = Resource.create!(name: "Bike-#{SecureRandom.hex(3)}", status: "active", resource_type: @rt)
    resource2.create_resource_stat!(data: { "mileage" => 1_000 })
    resource2.resource_prices.create!(user_type: "resident", hour_rate: 3, day_rate: 48, km_rate: 1, min_charge: 0)

    fresh = Booking.create!(
      resource: resource2, user: @member,
      destination: "Errand",
      start_at: Time.zone.local(2026, 7, 15, 9, 0),
      end_at:   Time.zone.local(2026, 7, 15, 13, 0),
      status: "active",
      start_mileage: 1_000
    )

    ReservationCompletionService.call(booking: fresh, ending_reading: 1_050)
    assert_equal "202607", fresh.reload.billing_month
  end
end
