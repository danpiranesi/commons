# Lets an admin see the system exactly as a member does, then come back.
#
# Deliberately outside the Admin namespace: while the preview is on, `admin?`
# is false and every admin page turns the user away -- so the way back has to
# live somewhere a member can reach. Both actions check the database flag
# (`current_user.admin?`), not the preview-aware helper, so only a real admin
# can enter or leave the preview.
class MemberPreviewsController < ApplicationController
  before_action :require_real_admin!

  def create
    session[:preview_as_member] = true
    redirect_to root_path, notice: t("member_preview.started")
  end

  def destroy
    session.delete(:preview_as_member)
    redirect_to admin_resources_path, notice: t("member_preview.ended")
  end

  private

  def require_real_admin!
    redirect_to root_path, alert: t("errors.not_authorized") unless current_user&.admin?
  end
end
