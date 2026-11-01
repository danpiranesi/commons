module Admin
  class ResourcesController < BaseController
    before_action :set_resource, only: [:show, :edit, :update, :destroy, :toggle_status, :recharge, :regenerate_qr_confirm, :regenerate_qr, :label]

    def index
      @resource_types = ResourceType.ordered.includes(resources: [:resource_prices, :resource_type])
    end

    def show
      @prices = @resource.resource_prices.index_by(&:user_type)
      @pricing_rules = @resource.pricing_rules.order(:min_days)
    end

    def new
      @resource = Resource.new
      @resource_types = ResourceType.ordered
      @available_accessories = load_available_accessories
      build_prices
    end

    def create
      @resource = Resource.new(resource_params)
      @resource_types = ResourceType.ordered

      if @resource.save
        save_prices
        save_pricing_rules
        save_compatibilities
        if params[:initial_mileage].present?
          stat = @resource.resource_stat || @resource.build_resource_stat
          stat.update!(data: { "mileage" => params[:initial_mileage].to_i })
        end
        redirect_to admin_resource_path(@resource), notice: t("admin.resources.notices.created")
      else
        build_prices
        @available_accessories = load_available_accessories
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @resource_types = ResourceType.ordered
      @available_accessories = load_available_accessories
      build_prices
    end

    def update
      @resource_types = ResourceType.ordered

      if @resource.update(resource_params)
        save_prices
        save_pricing_rules
        save_compatibilities
        if params[:initial_mileage].present?
          stat = @resource.resource_stat || @resource.build_resource_stat
          stat.update!(data: { "mileage" => params[:initial_mileage].to_i })
        end
        redirect_to admin_resource_path(@resource), notice: t("admin.resources.notices.updated")
      else
        build_prices
        @available_accessories = load_available_accessories
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @resource.bookings.exists?
        redirect_to admin_resource_path(@resource), alert: t("admin.resources.alerts.cannot_delete")
      else
        @resource.destroy!
        redirect_to admin_resources_path, notice: t("admin.resources.notices.deleted")
      end
    end

    def toggle_status
      case @resource.status
      when "active"
        @resource.update!(
          status: "unavailable",
          unavailable_reason: params[:reason],
          unavailable_until: params[:unavailable_until]
        )
        redirect_to admin_resource_path(@resource), notice: t("admin.resources.notices.marked_unavailable")
      when "unavailable"
        @resource.update!(status: "active", unavailable_reason: nil, unavailable_until: nil)
        redirect_to admin_resource_path(@resource), notice: t("admin.resources.notices.reactivated")
      end
    end

    # Deliberate interstitial before regenerating — this invalidates every printed
    # QR label for the vehicle, so it shouldn't be a one-click (or reflexive
    # dialog-dismiss) action.
    def regenerate_qr_confirm
    end

    def regenerate_qr
      @resource.regenerate_qr_token!
      redirect_to admin_resource_path(@resource), notice: t("admin.resources.notices.qr_regenerated")
    end

    def label
      pdf = LabelPdf.new(@resource, scan_url: vehicle_scan_url(@resource.qr_token)).render
      filename = "#{@resource.display_name.parameterize}-label.pdf"
      send_data pdf, filename: filename, type: "application/pdf", disposition: "inline"
    end

    def recharge
      if params[:clear]
        @resource.finish_recharge!
        redirect_to admin_resource_path(@resource), notice: t("admin.resources.notices.recharge_cleared")
      else
        recharge_until = Time.zone.parse(params[:recharge_until]) rescue nil
        if recharge_until
          @resource.start_recharge!(recharge_until)
          redirect_to admin_resource_path(@resource), notice: t("admin.resources.notices.recharging_until", time: recharge_until.strftime('%H:%M on %-d %b'))
        else
          redirect_to admin_resource_path(@resource), alert: t("admin.resources.alerts.recharge_time_required")
        end
      end
    end

    private

    def set_resource
      @resource = Resource.find(params[:id])
    end

    def resource_params
      params.require(:resource).permit(:name, :port, :description, :resource_type_id, :electric, :regular_driver, :regular_user_id, :color, :make, :location, :license_number, :damage_notes, :inventory_count)
    end

    def build_prices
      User::USER_TYPES.each do |ut|
        @resource.resource_prices.build(user_type: ut) unless @resource.resource_prices.any? { |rp| rp.user_type == ut }
      end
    end

    def save_prices
      (params[:prices] || {}).each do |user_type, price_attrs|
        price = @resource.resource_prices.find_or_initialize_by(user_type: user_type)
        price.update!(
          hour_rate: price_attrs[:hour_rate] || 0,
          day_rate: price_attrs[:day_rate] || 0,
          km_rate: price_attrs[:km_rate] || 0,
          min_charge: price_attrs[:min_charge] || 0
        )
      end
    end

    def save_pricing_rules
      @resource.pricing_rules.destroy_all
      (params[:pricing_rules] || []).each do |rule_attrs|
        next if rule_attrs[:min_days].blank? && rule_attrs[:max_days].blank?
        @resource.pricing_rules.create!(
          min_days: rule_attrs[:min_days].presence,
          max_days: rule_attrs[:max_days].presence,
          multiplier: rule_attrs[:multiplier],
          description: rule_attrs[:description]
        )
      end
    end

    def load_available_accessories
      accessory_types = ResourceType.where.not(name: %w[Car Bicycle])
      Resource.where(resource_type: accessory_types, status: %w[active unavailable])
        .includes(:resource_type)
        .order("resource_types.sort_order, resources.name")
    end

    def save_compatibilities
      accessory_ids = Array(params[:accessory_ids]).map(&:to_i).reject(&:zero?)
      @resource.resource_compatibilities.destroy_all
      accessory_ids.each do |aid|
        @resource.resource_compatibilities.create!(accessory_id: aid)
      end
    end
  end
end
