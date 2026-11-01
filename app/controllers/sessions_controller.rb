class SessionsController < ApplicationController
  layout "minimal"
  skip_before_action :authenticate_user!

  def new
    # Stash the intended destination before any branch, so both dev-bypass and
    # the real SSO round trip return the user there (return-to for booking from
    # the public schedule).
    session[:sso_return] = params[:return] if params[:return].present?

    if Rails.application.config.discourse_dev_bypass
      dev_login
      return
    end

    nonce = SecureRandom.hex(16)
    session[:sso_nonce] = nonce

    callback_url = "#{Rails.application.config.booking_base_url}/auth/callback"
    redirect_to DiscourseSso.new.login_url(return_url: callback_url, nonce: nonce), allow_other_host: true
  end

  def callback
    sso = DiscourseSso.new
    user_data = sso.parse_callback(sso: params[:sso], sig: params[:sig])

    if user_data[:nonce] != session.delete(:sso_nonce)
      redirect_to login_path, alert: t("sessions.alerts.login_failed")
      return
    end

    unless sso.access_allowed?(user_data[:groups])
      reset_session
      redirect_to login_path, alert: t("sessions.alerts.access_denied") and return
    end

    user = find_or_create_user(user_data, sso)
    session[:user_id] = user.id
    session[:groups] = user_data[:groups]
    dest = session.delete(:sso_return).presence || root_path
    redirect_to dest, allow_other_host: true
  rescue DiscourseSso::InvalidSignatureError
    redirect_to login_path, alert: t("sessions.alerts.invalid_signature")
  end

  def destroy
    kiosk = kiosk_mode?
    reset_session
    if kiosk
      # Kiosk logout is local only — drop the booking session and return the wall
      # to its idle schedule, without killing the member's global Discourse SSO.
      redirect_to schedule_path
    elsif Rails.application.config.discourse_dev_bypass
      redirect_to login_path
    else
      redirect_to "#{Rails.application.config.discourse_url}/logout", allow_other_host: true
    end
  end

  private

  def dev_login
    user = User.find_by(discourse_id: 1) || User.create!(
      discourse_id: 1,
      name: "Dev Admin",
      email: "admin@example.org",
      user_type: "resident",
      admin: true
    )
    session[:user_id] = user.id
    redirect_to session.delete(:sso_return).presence || root_path
  end

  def find_or_create_user(data, sso)
    user = User.find_by(discourse_id: data[:discourse_id]) ||
           User.find_or_initialize_by(email: data[:email])

    # A name an admin has set (the member's real name) beats the forum's, which
    # may be an alias.
    user.name = data[:name] unless user.name_set_by_admin? && user.name.present?
    user.assign_attributes(
      discourse_id: data[:discourse_id],
      email: data[:email],
      discourse_username: data[:username],
      user_type: sso.user_type_from_groups(data[:groups]),
      admin: sso.admin_from_groups?(data[:groups])
    )
    user.save!
    user
  end
end
