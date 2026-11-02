require "test_helper"

class DemoModeTest < ActionDispatch::IntegrationTest
  setup { Rails.application.config.demo_mode = true }
  teardown { Rails.application.config.demo_mode = false }

  test "a visitor is signed in as a fresh guest without a login step" do
    assert_difference "User.count", 1 do
      get root_path
    end

    assert_response :success
    guest = User.order(:id).last
    assert guest.admin?
    assert_match guest.name, response.body
    assert_match I18n.t("demo.banner"), response.body
  end

  test "the same visitor keeps their guest account across requests" do
    get root_path
    assert_no_difference "User.count" do
      get root_path
    end
  end

  test "logging out starts over with a new guest" do
    get root_path
    first_guest = User.order(:id).last

    delete logout_path
    follow_redirect!

    assert_response :success
    assert_not_equal first_guest, User.order(:id).last
  end

  test "resetting wipes guest activity and restores the seeds" do
    get root_path
    assert User.where("email LIKE 'guest-%'").exists?

    DemoResetJob.perform_now

    assert_not User.where("email LIKE 'guest-%'").exists?, "guests are gone"
    assert User.exists?(discourse_id: 1), "seeded admin is back"
  end

  test "nothing changes when demo mode is off" do
    Rails.application.config.demo_mode = false

    assert_no_difference "User.count" do
      get root_path
    end
    assert_redirected_to login_path(return: "/")
  end
end
