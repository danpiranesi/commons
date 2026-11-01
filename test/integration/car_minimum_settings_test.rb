require "test_helper"

# The car minimum price and home-car selection, edited on the Settings page.
class CarMinimumSettingsTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  def make_car(name)
    rt = ResourceType.find_or_create_by!(name: "Car") { |r| r.billing_type = "per_day_and_km"; r.sort_order = 1 }
    Resource.create!(name: name, status: "active", resource_type: rt)
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "the settings page lists cars with home-car checkboxes" do
    car = make_car("VW-#{SecureRandom.hex(3)}")
    sign_in(admin)
    get admin_homepage_header_path
    assert_response :success
    assert_match I18n.t("admin.site_settings.minimum.card_title"), @response.body
    assert_match car.display_name, @response.body
  end

  test "saving updates the minimums and the home-car flags" do
    a = make_car("A-#{SecureRandom.hex(3)}")
    b = make_car("B-#{SecureRandom.hex(3)}")
    sign_in(admin)

    patch admin_homepage_header_path, params: {
      site_setting: { car_minimum_price: "25", home_car_minimum_price: "12" },
      home_car_ids: [a.id]
    }
    assert_redirected_to admin_homepage_header_path

    assert_equal 25.0, SiteSetting.instance.car_minimum_price.to_f
    assert_equal 12.0, SiteSetting.instance.home_car_minimum_price.to_f
    assert a.reload.home_car?, "A is now a home car"
    refute b.reload.home_car?, "B is not"
  end

  test "unticking a home car clears its flag" do
    a = make_car("A-#{SecureRandom.hex(3)}")
    a.update!(home_car: true)
    sign_in(admin)

    patch admin_homepage_header_path, params: {
      site_setting: { car_minimum_price: "20", home_car_minimum_price: "10" }
      # no home_car_ids → all cleared
    }
    refute a.reload.home_car?
  end
end
