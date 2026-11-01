module Admin
  class ResourceTypesController < BaseController
    before_action :set_resource_type, only: [:edit, :update]

    def index
      @resource_types = ResourceType.ordered.includes(:resources)
    end

    def new
      @resource_type = ResourceType.new
    end

    def create
      @resource_type = ResourceType.new(resource_type_params)
      if @resource_type.save
        redirect_to admin_resource_types_path, notice: t("admin.resource_types.notices.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @resource_type.update(resource_type_params)
        redirect_to admin_resource_types_path, notice: t("admin.resource_types.notices.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_resource_type
      @resource_type = ResourceType.find(params[:id])
    end

    def resource_type_params
      params.require(:resource_type).permit(:name, :billing_type, :icon, :color, :sort_order, :inherit_rules_from_car)
    end
  end
end
