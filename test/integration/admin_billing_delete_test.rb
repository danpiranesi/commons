require "test_helper"

# Deleting a trip from the monthly billing screen: for a car that failed or a
# missing key, where the member should not pay at all. The charge is refunded
# (the ledger is never edited) and the trip leaves every billing report.
class AdminBillingDeleteTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 7, 15, 12, 0, 0)
    @admin = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                          name: "Anna Admin", email: "anna#{SecureRandom.hex(3)}@example.com",
                          user_type: "resident", admin: true)
    @member = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                           name: "erik", email: "erik#{SecureRandom.hex(3)}@example.com",
                           user_type: "resident")
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    @resource = Resource.create!(name: "VW-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    @booking = Booking.create!(resource: @resource, user: @member, destination: "Town",
                               start_at: Time.zone.local(2026, 7, 14, 9, 0), end_at: Time.zone.local(2026, 7, 14, 17, 0),
                               status: "returned", completed_at: Time.zone.local(2026, 7, 14, 16, 0),
                               start_mileage: 50_000, end_mileage: 50_100, total_amount: 300, billing_month: "202607")
    @member.create_account! unless @member.account
    @member.account.transactions.create!(user: @member, booking: @booking, amount: -300, description: "charge")
  end

  teardown { travel_back }

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  test "an admin deletes a trip: the charge is refunded and it leaves the month" do
    sign_in @admin
    delete admin_booking_path(@booking)
    assert_redirected_to admin_monthly_overview_path(billing_month: "202607")

    @booking.reload
    assert_equal "cancelled", @booking.status
    assert_equal 0, Transaction.where(booking: @booking).sum(:amount), "the ledger nets to nothing"
    assert_equal 2, Transaction.where(booking: @booking).count, "the original charge is kept and offset"

    get admin_monthly_overview_path(billing_month: "202607")
    assert_no_match edit_admin_booking_path(@booking), @response.body
  end

  test "deleting twice does not refund twice" do
    sign_in @admin
    delete admin_booking_path(@booking)
    delete admin_booking_path(@booking)
    assert_equal 0, Transaction.where(booking: @booking).sum(:amount)
  end

  test "a closed month cannot be changed" do
    ClosedBillingMonth.create!(billing_month: "202607")
    sign_in @admin
    delete admin_booking_path(@booking)
    assert_equal "returned", @booking.reload.status
  end

  test "members cannot delete from billing" do
    sign_in @member
    delete admin_booking_path(@booking)
    assert_equal "returned", @booking.reload.status
  end

  test "members are listed alphabetically regardless of case" do
    other = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Bente",
                         email: "b#{SecureRandom.hex(3)}@example.com", user_type: "resident")
    Booking.create!(resource: @resource, user: other, destination: "Town",
                    start_at: Time.zone.local(2026, 7, 13, 9, 0), end_at: Time.zone.local(2026, 7, 13, 10, 0),
                    status: "returned", completed_at: Time.zone.local(2026, 7, 13, 10, 0),
                    total_amount: 10, billing_month: "202607")
    sign_in @admin
    get admin_monthly_overview_path(billing_month: "202607")
    body = @response.body
    assert body.index(">Bente<") < body.index(">erik<"), "Bente sorts before erik"
  end
end
