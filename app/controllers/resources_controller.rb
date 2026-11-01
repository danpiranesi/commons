class ResourcesController < ApplicationController
  def show
    @resource = Resource.find(params[:id])
    @price = @resource.price_for(current_user.user_type)
    @accessories = @resource.accessories.includes(:resource_type, :resource_prices).where(status: %w[active unavailable])
    @compatible_with = @resource.compatible_with.includes(:resource_type).where(status: %w[active unavailable]) if @resource.resource_type.billing_type != "per_day_and_km"
    @future_bookings = @resource.bookings
      .where(status: %w[active awaiting_return])
      .where("end_at > ?", Time.current)
      .includes(:user)
      .order(:start_at)
    @detail_template = ResourceDetailTemplate.for(@resource.resource_type)
  end

  def update
    @resource = Resource.find(params[:id])

    unless admin?
      redirect_to resource_path(@resource), alert: t("errors.not_authorized")
      return
    end

    @resource.update!(params.require(:resource).permit(:regular_driver))
    redirect_to resource_path(@resource), notice: t("resources.notices.updated")
  end
end
