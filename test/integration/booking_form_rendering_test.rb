require "test_helper"

# The booking form carries several hand-written controls (the Monday-first date
# picker, the destination suggestions, the repeat options). This renders them so
# a template mistake fails here rather than in front of a member.
class BookingFormRenderingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Helene",
                         email: "#{SecureRandom.hex(4)}@example.com", user_type: "resident")
    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    @car = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    get "/test/sign_in/#{@user.id}"
  end

  test "the new booking form renders the Monday-first date picker" do
    get new_booking_path(resource_id: @car.id)
    assert_response :success
    assert_match 'data-controller="date-picker"', @response.body
    # The native <input type="date"> opens a Sunday-first dialog.
    assert_no_match(/name="booking_start\[date\]" [^>]*type="date"/, @response.body)
  end

  test "the destination field offers the list and still takes free text" do
    SiteSetting.instance.update!(destinations_enabled: true)
    get new_booking_path(resource_id: @car.id)
    assert_response :success
    assert_match "<datalist", @response.body
    assert_match 'list="destination-suggestions"', @response.body
    assert_match I18n.t("bookings.form.destination_private_label"), @response.body
  end

  test "the private-destination wording is neutral" do
    assert_equal "Privat", Booking::PRIVATE_DESTINATION
    assert_not_equal "Ikke din sag", I18n.t("bookings.form.destination_private_label", locale: :da)
    assert_not_equal "None of your business", I18n.t("bookings.form.destination_private_label", locale: :en)
  end

  test "the repeat options offer more than the current week" do
    get new_booking_path(resource_id: @car.id)
    assert_response :success
    assert_match 'name="recurring_weeks"', @response.body
  end

  test "the edit form can correct which group a trip is charged to" do
    b = Booking.create!(resource: @car, user: @user, destination: "Town", status: "active",
                        start_at: 1.day.from_now, end_at: 1.day.from_now + 2.hours)
    category = BillingCategory.create!(key: "grp-#{SecureRandom.hex(3)}", name_da: "Gruppe",
                                       rate_mode: "multiplier", rate_value: 1.0)
    BillingGroup.create!(name: "Carpool", code: "carpool-#{SecureRandom.hex(3)}",
                         billing_category: category, active: true)
    BillingGroupMembership.create!(user: @user, billing_group: BillingGroup.last)

    get edit_booking_path(b)
    assert_response :success
    assert_match 'name="booking[billing_group_id]"', @response.body
  end
end
