require "test_helper"

# Batch label printing: multi-select on the resources list → layout page → PDF.
class AdminLabelSheetsTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                            name: "Admin", email: "a#{SecureRandom.hex(4)}@example.com",
                            user_type: "resident", admin: true)
  end

  def cars
    @cars ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      [Resource.create!(name: "VW One", status: "active", resource_type: rt),
       Resource.create!(name: "VW Two", status: "active", resource_type: rt)]
    end
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "resources list offers multi-select and a print button" do
    cars
    sign_in(admin)

    get admin_resources_path

    assert_response :success
    assert_match I18n.t("admin.labels.print_button"), @response.body
    assert_select "input[type=checkbox][name=?][value=?]", "resource_ids[]", cars.first.id.to_s
    assert_select "form[action=?]", new_admin_label_sheet_path
  end

  test "layout page shows the selection, defaults and sheet count" do
    sign_in(admin)

    get new_admin_label_sheet_path, params: { resource_ids: cars.map(&:id) }

    assert_response :success
    assert_match "VW One", @response.body
    assert_match I18n.t("admin.labels.scale_warning"), @response.body
    # Letter defaults are pre-filled and adjustable
    assert_select "input[name=label_width][value=?]", "99.1"
    assert_select "input[name=label_height][value=?]", "67.7"
    assert_select "input[name=page_width][value=?]", "215.9"
    assert_select "input[name=start_offset]"
  end

  test "generates a PDF for the selected vehicles" do
    sign_in(admin)

    post admin_label_sheet_path, params: { resource_ids: cars.map(&:id) }

    assert_response :success
    assert_equal "application/pdf", @response.media_type
    assert @response.body.start_with?("%PDF")
  end

  test "custom dimensions are honoured" do
    sign_in(admin)

    post admin_label_sheet_path, params: {
      resource_ids: cars.map(&:id),
      page_width: 210, page_height: 297, columns: 3, rows: 8,
      label_width: 70, label_height: 37, outlines: "1"
    }

    assert_response :success
    assert_equal "application/pdf", @response.media_type
  end

  test "selecting nothing sends you back with a message" do
    sign_in(admin)
    get new_admin_label_sheet_path
    assert_redirected_to admin_resources_path
    assert_equal I18n.t("admin.labels.none_selected"), flash[:alert]
  end

  test "non-admins cannot print labels" do
    member = User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                          name: "M", email: "m#{SecureRandom.hex(4)}@example.com",
                          user_type: "resident", admin: false)
    sign_in(member)
    get new_admin_label_sheet_path, params: { resource_ids: cars.map(&:id) }
    assert_redirected_to root_path
  end
end
