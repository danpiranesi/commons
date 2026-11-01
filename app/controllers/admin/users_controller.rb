module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:edit, :update]

    def index
      @users = User.all.sort_by(&:name_sort_key)
    end

    # GET /admin/users/search?q=ali
    # Returns JSON: [{id, name, email, user_type, initials, housing_unit}, ...]
    def search
      q = params[:q].to_s.strip
      @users = if q.length >= 2
        User.where(
          "name ILIKE :q OR email ILIKE :q OR initials ILIKE :q OR housing_unit ILIKE :q",
          q: "%#{q}%"
        ).order(:name).limit(10)
      else
        User.none
      end

      render json: @users.map { |u|
        { id: u.id, name: u.name, email: u.email,
          user_type: u.user_type, initials: u.initials,
          housing_unit: u.housing_unit }
      }
    end

    def edit
    end

    def update
      @user.assign_attributes(user_params)
      apply_display_name
      @user.working_hours = parsed_working_hours
      if @user.save
        redirect_to admin_users_path, notice: t("admin.users.notices.updated", name: @user.name)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    # Working hours arrive as user[working_hours][cwday][start|end]. Keep only days
    # with a valid start < end; drop the rest. Converted to a plain hash first,
    # because ActionController::Parameters has no each_with_object.
    def parsed_working_hours
      raw = params.dig(:user, :working_hours) || {}
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)

      raw.each_with_object({}) do |(cwday, times), result|
        next unless times.is_a?(Hash)
        s = times["start"].to_s.strip
        e = times["end"].to_s.strip
        next if s.blank? || e.blank? || e <= s
        result[cwday.to_s] = { "start" => s, "end" => e }
      end
    end

    # The name shown everywhere in the booking system. Setting it pins it, so the
    # forum login stops replacing it with the member's forum alias. Clearing the
    # field hands it back to the forum (refreshed at their next login).
    def apply_display_name
      return unless params[:user]&.key?(:name)

      submitted = params[:user][:name].to_s.squish
      if submitted.blank?
        @user.name_set_by_admin = false
      elsif submitted != @user.name
        @user.name = submitted
        @user.name_set_by_admin = true
      end
    end

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(
        :phone, :email, :username, :user_type, :initials, :housing_unit,
        :accounting_account, :accounting_name, :billing_category_id, :business_override
      )
    end
  end
end
