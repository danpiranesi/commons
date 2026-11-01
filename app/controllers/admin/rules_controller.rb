module Admin
  # The Rules page: a clickable lifecycle flowchart (Booking → Check-out → During
  # → Check-in). Selecting a stage edits that stage's rules for the chosen resource
  # type. One stage saved at a time; the rest of the type's rules are preserved.
  class RulesController < BaseController
    STAGES = BookingRules::STAGES

    def show
      # Types that inherit the car's rules aren't editable on their own.
      @resource_types = ResourceType.with_own_rules.order(:sort_order, :name)
      @resource_type  = selected_type
      redirect_to(admin_resources_path, alert: t("rules.no_types")) and return unless @resource_type

      @rules = BookingRules.for(@resource_type)
    end

    # Every stage present in the form is saved in a single write.
    def update
      resource_type = ResourceType.find(params[:resource_type_id])

      merged = resource_type.booking_rules.deep_dup
      STAGES.each do |stage|
        next unless params.dig(:rules, stage)
        merged[stage] = sanitized_stage(stage)
      end
      resource_type.update!(booking_rules: merged)

      redirect_to admin_rules_path(resource_type_id: resource_type.id), notice: t("rules.saved")
    end

    private

    def selected_type
      types = ResourceType.with_own_rules.order(:sort_order, :name)
      params[:resource_type_id].present? ? types.find_by(id: params[:resource_type_id]) : types.first
    end

    # Build a clean, whitelisted hash for the submitted stage. Buffers are clamped
    # to a sane range; booleans are cast from checkbox values.
    def sanitized_stage(stage)
      s = params.fetch(:rules, {}).fetch(stage, {})
      case stage
      when "checkout"
        { "buffer_minutes" => clamp(s[:buffer_minutes], 0, 180),
          "require_odometer" => boolean(s[:require_odometer]) }
      when "during"
        { "allow_extension" => boolean(s[:allow_extension]),
          "edit_shorten_penalty_hours" => clamp(s[:edit_shorten_penalty_hours], 0, 24) }
      when "checkin"
        { "buffer_minutes" => clamp(s[:buffer_minutes], 0, 180),
          "require_confirmation" => boolean(s[:require_confirmation]),
          "max_km_per_trip" => clamp(s[:max_km_per_trip], 1, 100_000),
          "overdue_after_minutes" => clamp(s[:overdue_after_minutes], 0, 1440),
          "grace_minutes" => clamp(s[:grace_minutes], 0, 29) }
      else
        {}
      end
    end

    def clamp(value, min, max)
      value.to_i.clamp(min, max)
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end
  end
end
