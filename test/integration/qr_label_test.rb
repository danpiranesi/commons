require "test_helper"

# QR token regeneration and the printable label PDF.
class QrLabelTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      discourse_id: SecureRandom.random_number(1_000_000_000),
      name: "Admin", email: "admin_qr@example.com",
      user_type: "resident", admin: true
    )
    @member = User.create!(
      discourse_id: SecureRandom.random_number(1_000_000_000),
      name: "Member", email: "member_qr@example.com",
      user_type: "resident"
    )
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    @resource = Resource.create!(
      name: "Peugeot Test", status: "active", resource_type: rt,
      port: "E-46", color: "Hvid", make: "Peugeot", license_number: "AB 12 345"
    )
  end

  def sign_in(user) = get("/test/sign_in/#{user.id}")

  # --- Label PDF ---

  test "label action returns a PDF" do
    sign_in @admin
    get label_admin_resource_path(@resource)
    assert_response :success
    assert_equal "application/pdf", response.content_type
    assert response.body.start_with?("%PDF")
  end

  test "label PDF is substantial (QR matrix was drawn)" do
    sign_in @admin
    get label_admin_resource_path(@resource)
    # A label with a full QR code should be well over 10 KB
    assert response.body.bytesize > 10_000, "PDF too small — QR code likely missing"
  end

  test "non-admin cannot download label" do
    sign_in @member
    get label_admin_resource_path(@resource)
    assert_response :redirect
  end

  # --- QR regeneration ---

  test "regenerate_qr replaces the qr_token" do
    sign_in @admin
    old_token = @resource.qr_token
    post regenerate_qr_admin_resource_path(@resource)
    assert_redirected_to admin_resource_path(@resource)
    assert_not_equal old_token, @resource.reload.qr_token
    assert @resource.qr_token.present?
  end

  test "old qr_token no longer works after regeneration" do
    sign_in @admin
    old_token = @resource.qr_token
    post regenerate_qr_admin_resource_path(@resource)
    # QR scan with old token should 404
    get vehicle_scan_path(old_token)
    assert_response :not_found
  end

  test "new qr_token works after regeneration" do
    sign_in @admin
    post regenerate_qr_admin_resource_path(@resource)
    new_token = @resource.reload.qr_token
    get vehicle_scan_path(new_token)
    assert_response :success
  end

  test "non-admin cannot regenerate QR" do
    sign_in @member
    old_token = @resource.qr_token
    post regenerate_qr_admin_resource_path(@resource)
    assert_response :redirect
    assert_equal old_token, @resource.reload.qr_token
  end
end
