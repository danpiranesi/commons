module Admin
  # Three sub-pages toggled by ?section=:
  #   card           — per-type card template (title + 2 subtitle rows) for the calendar
  #   resource_detail — which fields appear on resources#show
  #   booking_detail  — which fields appear on bookings#show
  class DesignController < BaseController
    SECTIONS = %w[card resource_detail booking_detail].freeze

    def show
      @resource_types = ResourceType.order(:sort_order, :name)
      @resource_type  = selected_type
      redirect_to(admin_resources_path, alert: t("design.no_types")) and return unless @resource_type

      @section = params[:section].presence.then { |s| SECTIONS.include?(s) ? s : "card" }

      case @section
      when "card"
        @template      = ResourceCardTemplate.for(@resource_type)
        @fields        = ResourceCardTemplate.available_fields
        @sample        = @resource_type.resources.order(:name).first || sample_resource
        @sample_values = ResourceCardTemplate.sample_values(@sample)
      when "resource_detail"
        @detail_template = ResourceDetailTemplate.for(@resource_type)
        @fields          = ResourceDetailTemplate.available_fields
      when "booking_detail"
        @booking_template = BookingDetailTemplate.for(@resource_type)
        @fields           = BookingDetailTemplate.available_fields
      end
    end

    def update
      resource_type = ResourceType.find(params[:resource_type_id])
      section = params[:section].presence.then { |s| SECTIONS.include?(s) ? s : "card" }

      case section
      when "card"
        resource_type.update!(card_template: sanitized_card_template)
      when "resource_detail"
        resource_type.update!(detail_template: { "fields" => sanitized_field_list(ResourceDetailTemplate::FIELDS) })
      when "booking_detail"
        resource_type.update!(booking_template: { "fields" => sanitized_field_list(BookingDetailTemplate::FIELDS) })
      end

      redirect_to admin_design_path(resource_type_id: resource_type.id, section: section),
                  notice: t("design.saved")
    end

    private

    def selected_type
      types = ResourceType.order(:sort_order, :name)
      if params[:resource_type_id].present?
        types.find_by(id: params[:resource_type_id])
      else
        types.first
      end
    end

    def sanitized_card_template
      ResourceCardTemplate::SLOTS.index_with do |slot|
        cfg = params.dig(:template, slot) || {}
        {
          "fields"    => Array(cfg[:fields]).select { |k| ResourceCardTemplate::FIELDS.key?(k) },
          "separator" => cfg[:separator].to_s
        }
      end
    end

    # For detail/booking templates: just an ordered list of whitelisted field keys.
    def sanitized_field_list(registry)
      Array(params.dig(:detail, :fields)).select { |k| registry.key?(k) }
    end

    def sample_resource
      Resource.new(
        name: "Eksempel", port: "A-02", color: "Blå", make: "Toyota",
        license_number: "AB 12 345", location: "Carport 2",
        regular_driver: "Jane Doe", electric: true, resource_type: @resource_type
      )
    end
  end
end
