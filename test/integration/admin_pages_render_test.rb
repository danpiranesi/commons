require "test_helper"

# Smoke test: every admin form page renders (catches template/i18n errors in
# the settings layout and its components).
class AdminPagesRenderTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  setup { get "/test/sign_in/#{admin.id}" }

  test "settings page renders" do
    get admin_homepage_header_path
    assert_response :success
  end

  test "rules page renders" do
    ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    get admin_rules_path
    assert_response :success
  end

  test "resource type new and edit render" do
    get new_admin_resource_type_path
    assert_response :success

    rt = ResourceType.create!(name: "Trailer-#{SecureRandom.hex(3)}", billing_type: "per_day", sort_order: 3)
    get edit_admin_resource_type_path(rt)
    assert_response :success
    assert_match I18n.t("admin.resource_types.form.inherit_rules_label"), @response.body
  end

  test "billing group new and edit render" do
    cat = BillingCategory.create!(key: "member-#{SecureRandom.hex(3)}", name_da: "Medlem",
                                  rate_mode: "multiplier", rate_value: 1.0, collection: "bank", section: 1)
    get new_admin_billing_group_path
    assert_response :success

    group = BillingGroup.create!(name: "Garden-#{SecureRandom.hex(3)}", billing_category: cat)
    get edit_admin_billing_group_path(group)
    assert_response :success
  end

  test "user edit renders" do
    u = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                     name: "Mia", email: "m#{SecureRandom.hex(4)}@example.com", user_type: "resident")
    get edit_admin_user_path(u)
    assert_response :success
    assert_match I18n.t("admin.users.edit.contact_title"), @response.body
  end

  # ── Table / list pages (section-card framing + header tooltips) ──
  test "rates (Takster) page renders with header tooltips" do
    get admin_billing_categories_path
    assert_response :success
    assert_match I18n.t("admin.billing_categories.col_rule_tooltip"), @response.body
  end

  test "monthly overview renders" do
    get admin_monthly_overview_path
    assert_response :success
  end

  test "the index list pages render" do
    ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    get admin_resource_types_path
    assert_response :success
    assert_match I18n.t("admin.resource_types.index.col_billing_tooltip"), @response.body

    get admin_users_path
    assert_response :success
    get admin_billing_groups_path
    assert_response :success
    get admin_resources_path
    assert_response :success
  end
end
