require "test_helper"

# The member form on the admin side, submitted the way the browser posts it.
# Guards against the working-hours parser failing on the params object, which
# makes every save on the page fail.
class AdminUserEditTest < ActionDispatch::IntegrationTest
  setup do
    @admin  = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Anna",
                           email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident", admin: true)
    @member = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Beboer",
                           email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident")
    get "/test/sign_in/#{@admin.id}"
  end

  # Exactly the shape the browser posts: every field the form renders, blank or not.
  def submit(**overrides)
    patch admin_user_path(@member), params: { user: {
      phone: "", username: "", initials: "", housing_unit: "",
      accounting_account: "", accounting_name: "", billing_category_id: "",
      business_override: "0", user_type: "resident",
      working_hours: (1..7).to_h { |d| [d.to_s, { start: "", end: "" }] }
    }.merge(overrides) }
  end

  test "the konto and accounting name save" do
    submit(accounting_account: "4210", accounting_name: "Beboer B.")
    assert_redirected_to admin_users_path
    @member.reload
    assert_equal "4210", @member.accounting_account
    assert_equal "Beboer B.", @member.accounting_name
  end

  test "every other field on the form saves too" do
    category = BillingCategory.create!(key: "k-#{SecureRandom.hex(3)}", name_da: "Kat",
                                       rate_mode: "multiplier", rate_value: 1.0, personal: true)
    submit(phone: "2612 3456", username: "beboer", initials: "Be. B.", housing_unit: "North Wing",
           billing_category_id: category.id, business_override: "1", user_type: "employee")
    @member.reload
    assert_equal "2612 3456", @member.phone
    assert_equal "beboer",    @member.username
    assert_equal "Be. B.",    @member.initials
    assert_equal "North Wing", @member.housing_unit
    assert_equal category,    @member.billing_category
    assert @member.business_override?
    assert_equal "employee",  @member.user_type
  end

  test "working hours are kept for valid days and dropped for blank or reversed ones" do
    submit(working_hours: {
      "1" => { start: "08:00", end: "16:00" },
      "2" => { start: "",      end: "" },
      "3" => { start: "16:00", end: "08:00" }
    })
    assert_equal({ "1" => { "start" => "08:00", "end" => "16:00" } }, @member.reload.working_hours)
  end

  test "a validation failure is shown on the form rather than swallowed" do
    submit(email: "")
    assert_response :unprocessable_entity
    assert_match 'role="alert"', @response.body
  end

  # ── Display name ───────────────────────────────────────────────
  test "an admin sets a member's real name, and the forum login keeps it" do
    submit(name: "Jane Doe")
    @member.reload
    assert_equal "Jane Doe", @member.name
    assert @member.name_set_by_admin?

    user = SessionsController.new.send(:find_or_create_user,
      { discourse_id: @member.discourse_id, name: "Jane", email: @member.email, username: "jane", groups: [] },
      Struct.new(:x) { def user_type_from_groups(*) = "resident"; def admin_from_groups?(*) = false }.new(nil))
    assert_equal "Jane Doe", user.reload.name, "the forum alias must not replace it"
  end

  test "clearing the name hands it back to the forum" do
    @member.update!(name: "Pinned", name_set_by_admin: true)
    submit(name: "")
    @member.reload
    assert_equal "Pinned", @member.name, "kept until the next login"
    refute @member.name_set_by_admin?
  end
end
