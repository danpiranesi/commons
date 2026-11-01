require "test_helper"

class WizardControllerTest < ActionDispatch::IntegrationTest
  COPENHAGEN = ActiveSupport::TimeZone["Europe/Copenhagen"]

  setup do
    @user = User.create!(
      discourse_id: 9001,
      name: "Test User",
      email: "test_wizard@example.com",
      user_type: "resident",
      admin: false
    )
    # per_day billing so no destination validation on bookings
    @resource_type = ResourceType.create!(
      name: "TestVehicle",
      billing_type: "per_day",
      sort_order: 99
    )
    @resource = Resource.create!(
      name: "Test Car A",
      status: "active",
      resource_type: @resource_type
    )
    @period = BookingPeriod.create!(
      name: "Test Period",
      status: "open",
      start_date: Date.current - 1.day,
      end_date: Date.current + 30.days
    )
    sign_in
  end

  teardown do
    Booking.where(resource: [@resource]).destroy_all
    @resource.destroy
    @resource_type.destroy
    @period.destroy
    User.where(discourse_id: [9001, 9002]).destroy_all
  end

  # ── Availability query ────────────────────────────────────────────────

  test "results returns only free resources for the window" do
    day      = Date.current + 1 # tomorrow, so the slot is never in the past
    start_at = COPENHAGEN.local(day.year, day.month, day.day, 9, 0).utc
    end_at   = COPENHAGEN.local(day.year, day.month, day.day, 17, 0).utc

    other_user = User.create!(
      discourse_id: 9002, name: "Other", email: "other_w@example.com",
      user_type: "resident", admin: false
    )
    Booking.create!(
      resource: @resource, user: other_user,
      start_at: start_at - 1.hour, end_at: end_at + 1.hour,
      status: "active"
    )

    free_resource = Resource.create!(
      name: "Test Car B", status: "active", resource_type: @resource_type
    )

    get wizard_results_path(
      type_id:  @resource_type.id,
      start_at: start_at.iso8601,
      end_at:   end_at.iso8601
    )

    assert_response :success
    assert_includes response.body, "Test Car B"
    assert_not_includes response.body, "Test Car A"
  ensure
    free_resource&.destroy
    other_user&.destroy
  end

  test "results refuse a slot that has already started" do
    get wizard_results_path(type_id: @resource_type.id,
                            start_at: 1.day.ago.iso8601, end_at: (1.day.ago + 2.hours).iso8601)
    assert_redirected_to root_path
  end

  test "results leave out a car held for its fast bruger" do
    regular = User.create!(discourse_id: 9002, name: "Regular", email: "reg_w@example.com",
                           user_type: "resident", admin: false)
    @resource.update!(regular_user: regular)
    monday = Date.current.next_week(:monday) + 7 # a week whose hold is still active
    start_at = COPENHAGEN.local(monday.year, monday.month, monday.day, 9, 0)
    skip "no working hours configured for holds" unless @resource.held_for?(start_at, start_at + 2.hours, @user)

    get wizard_results_path(type_id: @resource_type.id, start_at: start_at.iso8601,
                            end_at: (start_at + 2.hours).iso8601)
    assert_response :success
    assert_not_includes response.body, "Test Car A"
  end

  # ── Bookable hours ────────────────────────────────────────────────────
  # Members on a late shift need to book the evening hours they actually drive.
  test "the time picker offers the whole day, not 06:00-22:00" do
    get wizard_times_path(type_id: @resource_type.id,
                          start_date: Date.current.iso8601,
                          end_date:   Date.current.iso8601)

    assert_response :success
    assert_match(/<option value="23"/, @response.body, "23:00 must be selectable")
    assert_match(/<option value="0"/,  @response.body, "midnight must be selectable")
  end

  # ── Timezone correctness ──────────────────────────────────────────────

  test "datetimes built from form fields are stored as UTC and display correctly" do
    start_date = (Date.current + 7.days)
    end_date   = start_date + 1.day

    @period.update!(end_date: end_date + 5.days)

    get wizard_results_path(
      type_id:    @resource_type.id,
      start_date: start_date.iso8601, start_hour: "9", start_min: "0",
      end_date:   end_date.iso8601,   end_hour: "17",  end_min: "0"
    )

    assert_response :success
    # 09:00 picked → 09:00 shown on the results page
    assert_includes response.body, "09:00"
    assert_includes response.body, "17:00"
  end

  # ── Date beyond the rolling booking horizon is rejected ───────────────
  # The horizon (today + N days), not a booking period, decides what is bookable.

  test "times redirects when dates are beyond the booking horizon" do
    horizon = SiteSetting.instance.booking_horizon_date
    skip "horizon is unlimited" if horizon.nil?
    outside_date = horizon + 5.days

    get wizard_times_path(
      type_id:    @resource_type.id,
      start_date: outside_date.iso8601,
      end_date:   outside_date.iso8601
    )

    assert_redirected_to root_path
    assert flash[:alert].present?
  end

  test "times allows dates inside the booking horizon" do
    inside_date = Date.current + 3

    get wizard_times_path(
      type_id:    @resource_type.id,
      start_date: inside_date.iso8601,
      end_date:   inside_date.iso8601
    )

    assert_response :success
  end

  # ── No open period shows empty state on root ──────────────────────────

  test "root hides wizard when no open period exists but still renders page" do
    @period.update!(status: "closed")
    get root_path
    assert_response :success
    assert_not_includes response.body, "Find a resource"
  ensure
    @period.update!(status: "open")
  end

  private

  def sign_in
    get "/test/sign_in/#{@user.id}"
    assert_response :ok
  end
end
