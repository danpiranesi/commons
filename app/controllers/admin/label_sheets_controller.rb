module Admin
  # Batch QR-label printing: pick vehicles on the resources list, tune the sheet
  # layout here, then generate a print-ready PDF.
  class LabelSheetsController < BaseController
    DIMENSIONS = %i[page_width page_height label_width label_height
                    margin_left margin_top gutter_x gutter_y offset_x offset_y].freeze
    COUNTS     = %i[columns rows start_offset].freeze

    def new
      @resources = selected_resources
      if @resources.empty?
        redirect_to admin_resources_path, alert: t("admin.labels.none_selected") and return
      end
      @layout = LabelSheetPdf::DEFAULTS.merge(layout_options)
      @sheets = LabelSheetPdf.sheets_needed(
        @resources.size,
        columns: @layout[:columns], rows: @layout[:rows], start_offset: @layout[:start_offset]
      )
    end

    def create
      resources = selected_resources
      if resources.empty?
        redirect_to admin_resources_path, alert: t("admin.labels.none_selected") and return
      end

      urls = resources.index_by(&:id).transform_values { |r| vehicle_scan_url(r.qr_token) }
      pdf  = LabelSheetPdf.new(resources, scan_urls: urls, **layout_options).render

      send_data pdf, filename: "qr-labels.pdf",
                     type: "application/pdf", disposition: "inline"
    end

    private

    # Only resources that actually have a token — a label without one is useless.
    def selected_resources
      ids = Array(params[:resource_ids]).map(&:to_i).reject(&:zero?)
      return Resource.none if ids.empty?

      Resource.where(id: ids).where.not(qr_token: nil)
              .includes(:resource_type).order(:name).to_a
    end

    # Coerce + clamp: a zero/negative dimension or a huge grid would otherwise
    # produce a broken PDF (or spin forever laying out slots).
    def layout_options
      opts = {}

      DIMENSIONS.each do |key|
        next if params[key].blank?
        value = params[key].to_s.tr(",", ".").to_f # accept Danish decimal comma
        opts[key] = key.to_s.start_with?("offset", "gutter") ? value.clamp(-50, 200)
                                                             : value.clamp(1, 2000)
      end
      # Offsets and gutters may legitimately be 0 or negative; sizes may not.
      %i[offset_x offset_y gutter_x gutter_y].each do |key|
        opts[key] = params[key].to_s.tr(",", ".").to_f.clamp(-50, 200) if params[key].present?
      end

      COUNTS.each do |key|
        next if params[key].blank?
        opts[key] = params[key].to_i
      end
      opts[:columns]      = opts[:columns].clamp(1, 12)       if opts.key?(:columns)
      opts[:rows]         = opts[:rows].clamp(1, 24)          if opts.key?(:rows)
      opts[:start_offset] = opts[:start_offset].clamp(0, 500) if opts.key?(:start_offset)

      opts[:outlines] = ActiveModel::Type::Boolean.new.cast(params[:outlines]) if params[:outlines].present?
      opts
    end
  end
end
