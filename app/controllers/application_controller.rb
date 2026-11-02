class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :mark_kiosk_device
  before_action :authenticate_user!
  before_action :set_locale

  helper_method :current_user, :logged_in?, :admin?, :kiosk_mode?

  private

  def current_user
    @current_user ||= begin
      user = User.find_by(id: session[:user_id]) if session[:user_id]
      # An admin who has switched to the member view carries that on the user
      # object, so `admin?` below and the model's own admin branches all agree.
      user.previewing_as_member = true if user&.admin? && session[:preview_as_member]
      user
    end
  end

  def logged_in?
    current_user.present?
  end

  def admin?
    current_user&.acting_admin?
  end

  def set_locale
    I18n.locale = current_user&.locale&.to_sym || I18n.default_locale
  end

  # The physical wall/kiosk device is configured once to open a URL with
  # ?kiosk=1; that flags this browser persistently so authenticated pages reached
  # from it (e.g. booking after tapping a slot) get the idle-logout treatment,
  # without imposing it on ordinary members on their own devices.
  def mark_kiosk_device
    cookies.permanent[:kiosk_mode] = "1" if params[:kiosk] == "1"
  end

  def kiosk_mode?
    cookies[:kiosk_mode].present?
  end

  def authenticate_user!
    unless logged_in?
      # Stash where they were headed (e.g. an open slot tapped on the wall
      # schedule) so SSO returns them there instead of the app root.
      redirect_to login_path(return: request.fullpath)
    end
  end

  def require_admin!
    unless admin?
      redirect_to root_path, alert: t("errors.not_authorized")
    end
  end

  # A caller-supplied redirect target, accepted only if it's a local relative
  # path (never an off-site "//host" redirect). Used so the shared end/extend
  # controllers can return to whichever page invoked them (QR page vs dashboard).
  def safe_internal_path(path)
    path if path.is_a?(String) && path.start_with?("/") && !path.start_with?("//", "/\\")
  end
end
