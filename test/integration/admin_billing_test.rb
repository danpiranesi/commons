require "test_helper"

# Admins assign a category to a person, create the groups a trip can be booked
# for, and set the rate once per category.
class AdminBillingTest < ActionDispatch::IntegrationTest
  setup { BillingCategory.seed_defaults! }

  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  def member(name = "Anna")
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{SecureRandom.hex(4)}@example.com", user_type: "resident")
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "rates page lists every category and shows the state rate" do
    sign_in(admin)
    get admin_billing_categories_path

    assert_response :success
    assert_match "Medlem", @response.body
    assert_match "K/S arbejdsgruppe", @response.body
    assert_select "input[name=?]", "rates[#{BillingCategory.find_by(key: 'ks_arbejdsgruppe').id}]"
  end

  test "an admin can change the state rate in one place" do
    ks = BillingCategory.find_by!(key: "ks_arbejdsgruppe")
    sign_in(admin)

    patch update_all_admin_billing_categories_path, params: { rates: { ks.id.to_s => "4,10" } }

    assert_redirected_to admin_billing_categories_path
    assert_equal 4.10, ks.reload.rate_value.to_f, "Danish decimal comma should be accepted"
  end

  test "an admin can create a group and it inherits the category rate" do
    ks = BillingCategory.find_by!(key: "ks_arbejdsgruppe")
    sign_in(admin)

    post admin_billing_groups_path, params: {
      billing_group: { name: "Kitchen", code: "KITCHEN", billing_category_id: ks.id, active: "1" }
    }

    assert_redirected_to admin_billing_groups_path
    group = BillingGroup.find_by!(name: "Kitchen")
    assert_equal ks, group.billing_category
    # 100 km at the state rate, not the vehicle's normal price.
    assert_equal 394.00, group.charge_for(normal_amount: 999.00, km: 100).to_f
  end

  test "an admin can assign a personal category to a member" do
    person = member("Kim")
    hp = BillingCategory.find_by!(key: "hp")
    sign_in(admin)

    patch admin_user_path(person), params: { user: { billing_category_id: hp.id } }

    assert_equal hp, person.reload.billing_category
  end

  test "a group with bookings is deactivated rather than deleted" do
    ks = BillingCategory.find_by!(key: "ks_arbejdsgruppe")
    group = BillingGroup.create!(name: "Garden", code: "GARDEN", billing_category: ks)
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    car = Resource.create!(name: "VW", status: "active", resource_type: rt)
    driver = member
    group.billing_group_memberships.create!(user: driver)
    Booking.create!(resource: car, user: driver, destination: "Town", billing_group: group,
                    start_at: 2.hours.ago, end_at: 1.hour.ago, status: "active")
    sign_in(admin)

    delete admin_billing_group_path(group)

    assert BillingGroup.exists?(group.id), "history must survive"
    assert_not group.reload.active?
  end

  test "an admin can change how a category is collected" do
    hp = BillingCategory.find_by!(key: "hp")
    sign_in(admin)

    patch update_all_admin_billing_categories_path, params: {
      rates: { hp.id.to_s => hp.rate_value.to_s },
      collection: { hp.id.to_s => "internal" }
    }

    assert_equal "internal", hp.reload.collection
  end

  test "an admin can set the default hourly rate for a resource type" do
    ResourceType.seed_default_rates!
    car = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    sign_in(admin)

    patch update_all_admin_billing_categories_path, params: {
      default_rates: { car.id.to_s => { "resident" => "7", "employee" => "9" } }
    }

    assert_equal 7.0, car.reload.default_hour_rate_for("resident").to_f
    assert_equal 9.0, car.default_hour_rate_for("employee").to_f
  end

  test "the rates page shows the collection dropdown and default rates" do
    ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    sign_in(admin)
    get admin_billing_categories_path

    assert_response :success
    assert_select "select[name=?]", "collection[#{BillingCategory.find_by(key: 'hp').id}]"
    assert_match I18n.t("admin.billing_categories.defaults_title"), @response.body
  end

  test "non-admins are kept out" do
    sign_in(member)
    get admin_billing_categories_path
    assert_redirected_to root_path
  end
end
