require "test_helper"

# Closing trips that were never checked in, receipts that show the period
# charged, admins handing a booking to another member, and work-group trips kept
# off the driver's personal account.
class TripReturnAndOwnershipTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers
  include ActionMailer::TestHelper

  setup do
    BillingCategory.seed_defaults!
    travel_to Time.zone.local(2026, 9, 23, 10, 58)
  end

  teardown { travel_back }

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  def make_user(name, **attrs)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{name.downcase}#{SecureRandom.hex(3)}@example.com", user_type: "resident", **attrs)
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      c  = Resource.create!(name: "Ioniq-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
      c.resource_prices.create!(user_type: "resident", hour_rate: 5, day_rate: 0, km_rate: 1, min_charge: 0)
      c.create_resource_stat!(data: { "mileage" => 151_084 })
      c
    end
  end

  def jake
    @jake ||= make_user("Jake")
  end

  # Booked 09-19 on the 22nd, never checked in, never ended.
  def forgotten_trip
    @forgotten_trip ||= Booking.create!(resource: car, user: jake, destination: "Town",
                                        start_at: Time.zone.local(2026, 9, 22, 9, 0),
                                        end_at:   Time.zone.local(2026, 9, 22, 19, 0),
                                        status: "active")
  end

  # --- Trips not closing -------------------------------------------------

  test "a trip past its end that was never checked in offers the end form, not the start form" do
    forgotten_trip
    get vehicle_scan_path(car.qr_token)

    assert_match I18n.t("reservations.completion.end_button"), @response.body
    assert_no_match(/#{Regexp.escape(I18n.t("reservations.check_in.button"))}/, @response.body)
  end

  test "the late return is ended from the last recorded reading, so the distance is kept" do
    forgotten_trip
    post reservation_completion_path,
         params: { token: car.qr_token, booking_id: forgotten_trip.id, ending_reading: 151_179, confirmed: "1" }

    forgotten_trip.reload
    assert_equal "returned", forgotten_trip.status
    assert_equal 95, forgotten_trip.km_driven
  end

  test "a trip past its end can no longer be checked in" do
    forgotten_trip
    post reservation_check_in_path, params: { token: car.qr_token, booking_id: forgotten_trip.id, starting_reading: 151_179 }

    assert_redirected_to vehicle_scan_path(car.qr_token)
    assert_equal I18n.t("reservations.flash.check_in_trip_over"), flash[:alert]
    assert_equal "active", forgotten_trip.reload.status
    assert_nil forgotten_trip.start_mileage
  end

  test "a driver who never checked in can end the trip before its time is up" do
    trip = Booking.create!(resource: car, user: jake, destination: "Town",
                           start_at: 2.hours.ago, end_at: 1.hour.from_now, status: "active")

    get vehicle_scan_path(car.qr_token)
    assert_match I18n.t("reservations.check_in.returning_instead"), @response.body

    post reservation_completion_path,
         params: { token: car.qr_token, booking_id: trip.id, ending_reading: 151_120, end_without_check_in: "1" }
    assert_response :success # km confirmation screen
    assert_match "end_without_check_in", @response.body

    post reservation_completion_path,
         params: { token: car.qr_token, booking_id: trip.id, ending_reading: 151_120,
                   end_without_check_in: "1", confirmed: "1" }
    assert_equal "returned", trip.reload.status
    assert_equal 36, trip.km_driven
  end

  # --- Receipts ----------------------------------------------------------

  test "the receipt shows the period charged, and the booked slot beside it" do
    forgotten_trip.update!(status: "returned", completed_at: Time.current, start_mileage: 151_084,
                           end_mileage: 151_179, total_amount: 130, billing_month: "202609")

    mail = ReceiptMailer.completion(forgotten_trip)
    text = mail.text_part.body.to_s

    # Returned at 10:58: the period is the billed one, rounded to the half hour.
    assert_match "Periode:     22.09.2026 09:00 – 23.09.2026 11:00", text
    assert_match "Booket:      22.09.2026 09:00 – 22.09.2026 19:00", text
    assert_match "Tid (26 t)", text
    assert_match "23.09.2026 11:00", mail.html_part.body.to_s
  end

  test "a trip returned on time shows a single period" do
    forgotten_trip.update!(status: "returned", completed_at: forgotten_trip.end_at, total_amount: 50, billing_month: "202609")

    text = ReceiptMailer.completion(forgotten_trip).text_part.body.to_s
    assert_match "Periode:     22.09.2026 09:00 – 22.09.2026 19:00", text
    assert_no_match(/Booket:/, text)
  end

  test "an admin can correct the starting reading of a trip that billed 0 km" do
    admin = make_user("Anna", admin: true)
    forgotten_trip.update!(status: "returned", completed_at: Time.current, start_mileage: 151_179,
                           end_mileage: 151_179, total_amount: 130, billing_month: "202609")

    sign_in admin
    patch admin_booking_path(forgotten_trip), params: { booking: { start_mileage: 151_084 } }

    forgotten_trip.reload
    assert_equal 151_084, forgotten_trip.start_mileage
    assert_equal 95, forgotten_trip.km_driven
  end

  # --- Admins changing who a booking belongs to --------------------------

  test "an admin can hand a booking to another member" do
    mikkel = make_user("Mikkel", admin: true)
    iver   = make_user("Iver")
    trip = Booking.create!(resource: car, user: mikkel, actual_driver: mikkel.name, destination: "Værksted",
                           start_at: 2.days.from_now, end_at: 2.days.from_now + 3.hours, status: "active")

    sign_in mikkel
    get edit_booking_path(trip)
    assert_match I18n.t("bookings.form.owner_title"), @response.body

    patch booking_path(trip), params: { target_user_id: iver.id, booking: { destination: "Værksted" } }

    trip.reload
    assert_equal iver, trip.user
    assert_equal "Iver", trip.actual_driver
  end

  test "a member cannot hand their booking to somebody else" do
    erik = make_user("Erik")
    maja = make_user("Maja")
    trip = Booking.create!(resource: car, user: erik, destination: "Town",
                           start_at: 2.days.from_now, end_at: 2.days.from_now + 3.hours, status: "active")

    sign_in erik
    patch booking_path(trip), params: { target_user_id: maja.id, booking: { destination: "Town" } }
    assert_equal erik, trip.reload.user
  end

  test "the admin member picker is wired to the field that is submitted" do
    sign_in make_user("Anna", admin: true)
    get new_booking_path(resource_id: car.id)

    picker = css_select("[data-controller='user-search']").first
    assert picker, "picker rendered"
    assert picker.at_css("input[name='target_user_id'][data-user-search-target='hidden']"),
           "the hidden field must be the controller's target, or picking a member does nothing"
  end

  # --- Work-group trips ----------------------------------------------------

  def group_trip(driver, group)
    Booking.create!(resource: car, user: driver, billing_group: group, destination: "Town",
                    start_at: Time.zone.local(2026, 9, 10, 9), end_at: Time.zone.local(2026, 9, 10, 12),
                    status: "returned", completed_at: Time.zone.local(2026, 9, 10, 12),
                    start_mileage: 100, end_mileage: 150, total_amount: 197, billing_month: "202609")
  end

  test "group trips stay off the driver's bank transfer and get their own total" do
    admin    = make_user("Anna", admin: true)
    emil     = make_user("Emil", accounting_account: "1234")
    workshop = BillingGroup.create!(name: "Workshop", billing_category: BillingCategory.find_by!(key: "ks_arbejdsgruppe"))
    workshop.billing_group_memberships.create!(user: emil)
    group_trip(emil, workshop)
    Booking.create!(resource: car, user: emil, destination: "Town",
                    start_at: Time.zone.local(2026, 9, 11, 9), end_at: Time.zone.local(2026, 9, 11, 12),
                    status: "returned", completed_at: Time.zone.local(2026, 9, 11, 12),
                    total_amount: 15, billing_month: "202609")

    sign_in admin
    get export_csv_admin_monthly_overview_path(billing_month: "202609", type: "biler")
    assert_match(/Emil.*;15,00/, @response.body)
    assert_no_match(/212,00|197,00/, @response.body)

    get admin_monthly_overview_path(billing_month: "202609")
    assert_match I18n.t("admin.monthly_overview.show.group_totals_title"), @response.body
    # The group trip is listed under the group (with who drove), not in Emil's
    # own list, where it would read as if he were paying for it.
    group_section, member_section = @response.body.split(I18n.t("admin.monthly_overview.show.trips_by_member_title"), 2)
    assert_match I18n.t("admin.monthly_overview.show.col_driver"), group_section
    assert_match "197,0 kr", group_section
    assert_no_match "197,0 kr", member_section
  end

  test "a returned group trip keeps its group label in the calendar" do
    emil  = make_user("Emil")
    workshop = BillingGroup.create!(name: "Workshop", billing_category: BillingCategory.find_by!(key: "ks_arbejdsgruppe"))
    workshop.billing_group_memberships.create!(user: emil)
    group_trip(emil, workshop)

    sign_in emil
    get root_path(date: "2026-09-10")
    assert_match "Workshop", @response.body
  end
end
