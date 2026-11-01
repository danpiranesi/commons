require "test_helper"

# The admin design editor: page renders, saving persists a whitelisted template,
# and the saved template flows through ResourceCardComponent into the resource list.
class AdminDesignTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  def sign_in(user)
    get "/test/sign_in/#{user.id}"
  end

  def car_type
    @car_type ||= ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}",
                                       billing_type: "per_day_and_km", sort_order: 1)
  end

  test "design page renders with the field palette and live-preview targets" do
    car_type
    sign_in(admin)

    get admin_design_path

    assert_response :success
    assert_select "[data-controller='design-editor']"
    assert_select "[data-design-editor-target='previewTitle']"
    assert_match I18n.t("design.fields.port"), @response.body
  end

  test "saving persists a template and rejects unknown fields" do
    sign_in(admin)

    patch admin_design_path, params: {
      resource_type_id: car_type.id,
      template: {
        title:     { fields: %w[port color make], separator: " " },
        subtitle1: { fields: %w[regular_driver bogus_field], separator: " · " },
        subtitle2: { fields: %w[location], separator: " · " }
      }
    }

    assert_redirected_to admin_design_path(resource_type_id: car_type.id, section: "card")
    stored = car_type.reload.card_template
    assert_equal %w[port color make], stored["title"]["fields"]
    assert_equal %w[regular_driver], stored["subtitle1"]["fields"], "unknown field should be dropped"
  end

  test "a saved template renders through the shared component on the admin list" do
    sign_in(admin)
    car_type.update!(card_template: {
      "title"     => { "fields" => %w[port], "separator" => " " },
      "subtitle1" => { "fields" => %w[regular_driver], "separator" => " " },
      "subtitle2" => { "fields" => [], "separator" => " " }
    })
    Resource.create!(name: "VW", status: "active", resource_type: car_type,
                     port: "Z-99", regular_driver: "Bob Driver")

    get admin_resources_path

    assert_response :success
    assert_match "Z-99", @response.body
    assert_match "Bob Driver", @response.body
  end

  test "non-admins are kept out" do
    member = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                          name: "Member", email: "m#{SecureRandom.hex(4)}@example.com",
                          user_type: "resident", admin: false)
    sign_in(member)

    get admin_design_path
    assert_redirected_to root_path
  end
end
