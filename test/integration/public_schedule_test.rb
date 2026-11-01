require "test_helper"

# The public wall schedule reads without login and shows cars only; protected
# pages bounce to login carrying a return path for the booking flow.
class PublicScheduleTest < ActionDispatch::IntegrationTest
  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
      Resource.create!(name: "VW Transporter", status: "active", resource_type: rt)
    end
  end

  def bicycle
    @bicycle ||= begin
      rt = ResourceType.create!(name: "Bicycle", billing_type: "free", sort_order: 2)
      Resource.create!(name: "Red Cargo Bike", status: "active", resource_type: rt)
    end
  end

  test "schedule is readable without logging in" do
    car
    get schedule_path
    assert_response :success
    assert_match I18n.t("schedule.title"), @response.body
    assert_match "VW Transporter", @response.body
  end

  test "schedule shows cars only, not other resource types" do
    car
    bicycle
    get schedule_path
    assert_response :success
    assert_match "VW Transporter", @response.body
    assert_no_match(/Red Cargo Bike/, @response.body)
  end

  test "self-refresh meta tag is present for the unattended display" do
    car
    get schedule_path
    assert_match %r{http-equiv="refresh"}, @response.body
  end

  test "the idle-reset controller is wired to the schedule path" do
    car
    get schedule_path
    assert_select "[data-controller='idle'][data-idle-url-value=?]", schedule_path
  end

  test "tapping a protected page while logged out redirects to login with a return path" do
    get new_booking_path(resource_id: car.id, date: Date.current)
    assert_response :redirect
    assert_match %r{/login\?return=}, @response.location
    assert_match CGI.escape("/bookings/new"), @response.location
  end
end
