require "test_helper"

# The destination list is admin-editable on the settings page, so each
# community can enter where its members drive without a developer.
class DestinationSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: "Anna",
                          email: "#{SecureRandom.hex(5)}@example.com", user_type: "resident",
                          admin: true)
    get "/test/sign_in/#{@admin.id}"
    SiteSetting.instance.update!(destinations: nil, destinations_enabled: true)
  end

  def save_destinations(list)
    patch admin_homepage_header_path, params: {
      site_setting: {
        destinations_json: list.to_json,
        car_minimum_price: SiteSetting.instance.car_minimum_price,
        home_car_minimum_price: SiteSetting.instance.home_car_minimum_price,
        booking_horizon_days: SiteSetting.instance.booking_horizon_days,
        home_car_max_hours: SiteSetting.instance.home_car_max_hours,
        finance_account: SiteSetting.instance.finance_account,
        destinations_enabled: "1"
      }
    }
  end

  test "the settings page shows the list that is in use" do
    get admin_homepage_header_path
    assert_response :success
    assert_match SiteSetting::DEFAULT_DESTINATIONS.first["cities"].first, @response.body
    assert_match "Omtrentlig afstand", @response.body
    assert_match "Under 25 km", @response.body
  end

  test "an admin can replace the whole list" do
    save_destinations([
      { "group" => "Egne steder", "cities" => ["Nordby", "Østby"] },
      { "group" => "Afstand",     "cities" => ["Under 10 km"] }
    ])

    assert_equal [
      { "group" => "Egne steder", "cities" => ["Nordby", "Østby"] },
      { "group" => "Afstand",     "cities" => ["Under 10 km"] }
    ], SiteSetting.instance.reload.destination_list
  end

  test "a saved list reaches the booking form's suggestions" do
    save_destinations([{ "group" => "Test", "cities" => ["Østby Strand"] }])

    rt = ResourceType.find_by(name: "Car") ||
         ResourceType.create!(name: "Car", billing_type: "per_day_and_km", sort_order: 1)
    car = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)

    get new_booking_path(resource_id: car.id)
    assert_response :success
    assert_match "Østby Strand", @response.body
    default_city = SiteSetting::DEFAULT_DESTINATIONS.first["cities"].first
    assert_no_match(/#{Regexp.escape(default_city)}/, @response.body, "the built-in default must give way to the saved list")
  end

  test "blank groups and blank entries are dropped rather than saved" do
    save_destinations([
      { "group" => "  ",      "cities" => ["Ignoreret"] },
      { "group" => "Rigtig",  "cities" => ["Nordby", "  ", ""] },
      { "group" => "Tom",     "cities" => [] }
    ])

    assert_equal [{ "group" => "Rigtig", "cities" => ["Nordby"] }],
                 SiteSetting.instance.reload.destination_list
  end

  test "a form posted without the editor field leaves the list alone" do
    save_destinations([{ "group" => "Behold mig", "cities" => ["Nordby"] }])

    patch admin_homepage_header_path, params: {
      site_setting: { homepage_header_da: "Hej", car_minimum_price: 20,
                      home_car_minimum_price: 10, booking_horizon_days: 45,
                      home_car_max_hours: 3, finance_account: "2400" }
    }

    assert_equal [{ "group" => "Behold mig", "cities" => ["Nordby"] }],
                 SiteSetting.instance.reload.destination_list
  end

  test "clearing every group falls back to the built-in list rather than leaving nothing" do
    save_destinations([{ "group" => "Noget", "cities" => ["Nordby"] }])
    save_destinations([])

    assert_equal SiteSetting::DEFAULT_DESTINATIONS, SiteSetting.instance.reload.destination_list
  end

  test "the saved order is the order shown — groups and entries alike" do
    save_destinations([
      { "group" => "Sidst først", "cities" => ["C", "A", "B"] },
      { "group" => "Først sidst", "cities" => ["Z"] }
    ])
    list = SiteSetting.instance.reload.destination_list
    assert_equal ["Sidst først", "Først sidst"], list.map { |g| g["group"] }
    assert_equal ["C", "A", "B"], list.first["cities"]

    get admin_homepage_header_path
    assert_response :success
    assert_match I18n.t("admin.site_settings.destinations.move_up"), @response.body
    # The editor renders in saved order, so what the admin sees is what members get.
    assert_operator @response.body.index("Sidst først"), :<, @response.body.index("Først sidst")
  end
end
