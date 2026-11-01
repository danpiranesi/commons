require "test_helper"

class AdminRulesTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  def car_type
    @car_type ||= ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}",
                                       billing_type: "per_day_and_km", sort_order: 1)
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "the rules page renders each editable lifecycle stage as a section" do
    car_type
    sign_in(admin)
    get admin_rules_path

    assert_response :success
    %w[checkout during checkin].each do |stage|
      assert_match I18n.t("rules.stages.#{stage}.label"), @response.body
    end
  end

  test "saving persists the submitted stages, clamped and cast, in one write" do
    sign_in(admin)

    patch admin_rules_path, params: {
      resource_type_id: car_type.id,
      rules: {
        checkout: { buffer_minutes: "30", require_odometer: "1" },
        checkin: { buffer_minutes: "999", require_confirmation: "0", max_km_per_trip: "500" }
      }
    }
    assert_redirected_to admin_rules_path(resource_type_id: car_type.id)
    car_type.reload
    assert_equal 30, car_type.booking_rules.dig("checkout", "buffer_minutes")
    assert_equal 180, car_type.booking_rules.dig("checkin", "buffer_minutes"), "clamped to max"
    assert_equal false, car_type.booking_rules.dig("checkin", "require_confirmation")
  end

  test "the edit-penalty and overdue knobs persist" do
    sign_in(admin)

    patch admin_rules_path, params: {
      resource_type_id: car_type.id, stage: "during",
      rules: { during: { allow_extension: "1", edit_shorten_penalty_hours: "3" } }
    }
    assert_equal 3, car_type.reload.booking_rules.dig("during", "edit_shorten_penalty_hours")

    patch admin_rules_path, params: {
      resource_type_id: car_type.id, stage: "checkin",
      rules: { checkin: { buffer_minutes: "0", require_confirmation: "1", max_km_per_trip: "2000", overdue_after_minutes: "20" } }
    }
    assert_equal 20, car_type.reload.booking_rules.dig("checkin", "overdue_after_minutes")
    assert_equal 3, car_type.booking_rules.dig("during", "edit_shorten_penalty_hours"), "during stage untouched"
  end

  test "non-admins are kept out" do
    member = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                          name: "M", email: "m#{SecureRandom.hex(4)}@example.com",
                          user_type: "resident", admin: false)
    sign_in(member)
    get admin_rules_path
    assert_redirected_to root_path
  end
end
