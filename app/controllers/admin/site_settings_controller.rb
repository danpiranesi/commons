module Admin
  # "Startsidehoved" — the editable info banner shown at the top of the calendar
  # homepage. One text field per locale, stored on the singleton SiteSetting row.
  class SiteSettingsController < BaseController
    def edit
      @site_setting = SiteSetting.instance
      @cars = Resource.cars
    end

    def update
      @site_setting = SiteSetting.instance
      @site_setting.assign_attributes(site_setting_params)
      apply_destinations
      if @site_setting.save
        save_home_cars
        redirect_to admin_homepage_header_path, notice: t("admin.site_settings.saved")
      else
        @cars = Resource.cars
        render :edit, status: :unprocessable_entity
      end
    end

    private

    # The destinations editor posts its whole state as JSON in destinations_json.
    # Parse + sanitize into the ordered [{group, cities}] shape; blank entries are
    # dropped. Left untouched (existing list kept) if nothing valid was submitted.
    def apply_destinations
      raw = params.dig(:site_setting, :destinations_json)
      return if raw.blank?

      parsed = JSON.parse(raw) rescue nil
      return unless parsed.is_a?(Array)

      @site_setting.destinations = parsed.filter_map do |g|
        next unless g.is_a?(Hash)
        group = g["group"].to_s.strip
        cities = Array(g["cities"]).map { |c| c.to_s.strip }.reject(&:blank?)
        next if group.blank? || cities.empty?
        { "group" => group, "cities" => cities }
      end
    end

    def site_setting_params
      params.require(:site_setting).permit(:homepage_header_da, :homepage_header_en,
                                           :car_minimum_price, :home_car_minimum_price,
                                           :booking_horizon_days, :home_car_max_hours,
                                           :finance_account, :destinations_enabled)
    end

    # The home-car checkboxes are submitted as a list of resource ids; everything
    # not ticked is cleared. Scoped to cars so no other resource can be flagged.
    def save_home_cars
      selected = Array(params[:home_car_ids]).map(&:to_i)
      Resource.cars.update_all(home_car: false)
      Resource.cars.where(id: selected).update_all(home_car: true) if selected.any?
    end
  end
end
