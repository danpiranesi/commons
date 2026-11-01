require "test_helper"

# Regenerating a QR token invalidates every printed label, so it goes through a
# deliberate confirm screen — viewing it must not change the token; only the POST
# does.
class RegenerateQrConfirmTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      Resource.create!(name: "VW", status: "active", resource_type: rt)
    end
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "the confirm screen renders and does NOT change the token" do
    original = car.qr_token
    sign_in(admin)

    get regenerate_qr_confirm_admin_resource_path(car)

    assert_response :success
    assert_match I18n.t("admin.resources.show.regenerate_confirm.confirm_button"), @response.body
    assert_equal original, car.reload.qr_token, "just viewing the confirm screen must not regenerate"
  end

  test "confirming (POST) regenerates the token" do
    original = car.qr_token
    sign_in(admin)

    post regenerate_qr_admin_resource_path(car)

    assert_redirected_to admin_resource_path(car)
    assert_not_equal original, car.reload.qr_token
    assert_equal 43, car.qr_token.length
  end

  test "non-admins cannot reach the confirm screen" do
    member = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                          name: "M", email: "m#{SecureRandom.hex(4)}@example.com",
                          user_type: "resident", admin: false)
    sign_in(member)
    get regenerate_qr_confirm_admin_resource_path(car)
    assert_redirected_to root_path
  end
end
