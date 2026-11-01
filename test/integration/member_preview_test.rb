require "test_helper"

# An admin can switch to the member view to see exactly what a member sees,
# and come back. While previewing, nothing admin-only may leak through -- not
# the nav link, not the admin pages, not the wider "on behalf of" list on the
# booking form -- and nothing about the account itself may change.
class MemberPreviewTest < ActionDispatch::IntegrationTest
  setup do
    @admin  = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Anna",
                           email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident", admin: true)
    @member = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Beboer",
                           email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident")
    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    @car = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
  end

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  test "an admin can enter the preview and the banner and way back appear" do
    sign_in @admin
    post member_preview_path
    follow_redirect!
    assert_match I18n.t("member_preview.banner"), @response.body
    assert_match I18n.t("member_preview.stop_button"), @response.body
  end

  test "while previewing, the admin link and admin pages are gone" do
    sign_in @admin
    post member_preview_path
    get root_path
    assert_no_match(/href="#{Regexp.escape(admin_resources_path)}"/, @response.body,
                    "the header's admin link must be gone")
    get admin_resources_path
    assert_redirected_to root_path
  end

  test "while previewing, the booking form offers only a member's own groups" do
    category = BillingCategory.create!(key: "g-#{SecureRandom.hex(3)}", name_da: "Gruppe",
                                       rate_mode: "multiplier", rate_value: 1.0)
    BillingGroup.create!(name: "Ikke min gruppe", code: SecureRandom.hex(3),
                         billing_category: category, active: true)

    sign_in @admin
    get new_booking_path(resource_id: @car.id)
    assert_match "Ikke min gruppe", @response.body, "an admin normally sees every group"

    post member_preview_path
    get new_booking_path(resource_id: @car.id)
    assert_no_match(/Ikke min gruppe/, @response.body, "a member would not see a group they are not in")
    assert_no_match(/#{Regexp.escape(I18n.t("bookings.form.booking_for_title"))}/, @response.body,
                    "the admin-only book-on-behalf block must be hidden too")
  end

  test "leaving the preview restores admin" do
    sign_in @admin
    post member_preview_path
    delete member_preview_path
    assert_redirected_to admin_resources_path
    get admin_resources_path
    assert_response :success
  end

  test "the account itself is never changed" do
    sign_in @admin
    post member_preview_path
    get root_path
    assert @admin.reload.admin?, "the database flag must be untouched"
  end

  test "a member cannot use the toggle to gain anything" do
    sign_in @member
    post member_preview_path
    assert_redirected_to root_path
    delete member_preview_path
    assert_redirected_to root_path
    get admin_resources_path
    assert_redirected_to root_path
  end

  test "the preview does not leak into another session" do
    sign_in @admin
    post member_preview_path
    # A fresh sign-in (new session) starts as a normal admin again.
    reset!
    sign_in @admin
    get root_path
    assert_match %(href="#{admin_resources_path}"), @response.body
  end
end
