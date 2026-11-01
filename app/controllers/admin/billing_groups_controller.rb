module Admin
  # Work groups, interest groups and shared accounts that a booking can be made
  # on behalf of. Each carries a category, and the category carries the rate.
  class BillingGroupsController < BaseController
    before_action :set_group, only: [:edit, :update, :destroy, :add_member, :remove_member]

    def index
      @groups = BillingGroup.includes(:billing_category).ordered
    end

    def new
      @group = BillingGroup.new(active: true)
    end

    def create
      @group = BillingGroup.new(group_params)
      if @group.save
        redirect_to admin_billing_groups_path, notice: t("admin.billing_groups.created", name: @group.name)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @group.update(group_params)
        redirect_to admin_billing_groups_path, notice: t("admin.billing_groups.updated", name: @group.name)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Groups with history are deactivated rather than deleted, so past bookings
    # keep showing who they were for.
    def destroy
      if @group.bookings.exists?
        @group.update!(active: false)
        redirect_to admin_billing_groups_path, notice: t("admin.billing_groups.deactivated", name: @group.name)
      else
        @group.destroy!
        redirect_to admin_billing_groups_path, notice: t("admin.billing_groups.deleted", name: @group.name)
      end
    end

    # Only members may book on behalf of a group, so this list is the access control.
    def add_member
      user = User.find_by(id: params[:user_id])
      if user
        @group.billing_group_memberships.find_or_create_by!(user: user)
        redirect_to edit_admin_billing_group_path(@group),
                    notice: t("admin.billing_groups.member_added", name: user.name)
      else
        redirect_to edit_admin_billing_group_path(@group),
                    alert: t("admin.billing_groups.member_not_found")
      end
    end

    def remove_member
      membership = @group.billing_group_memberships.find_by(user_id: params[:user_id])
      membership&.destroy
      redirect_to edit_admin_billing_group_path(@group),
                  notice: t("admin.billing_groups.member_removed")
    end

    private

    def set_group
      @group = BillingGroup.find(params[:id])
    end

    def group_params
      params.require(:billing_group).permit(:name, :code, :billing_category_id, :active)
    end
  end
end
