# Lays multiple vehicle QR labels out on a sheet of die-cut stickers.
#
# Defaults target US Letter with 99.1 × 67.7 mm stickers (2 × 4 = 8 per sheet),
# but every dimension is adjustable because the grid must match the *physical*
# sheet's die-cut positions, not numbers we invent. Sheets from different
# manufacturers differ, and printers drift — hence offset_x/offset_y for
# calibration and `outlines` for a test print on plain paper.
#
#   LabelSheetPdf.new(resources, scan_urls: {id => url}, columns: 2, rows: 4).render
class LabelSheetPdf
  DEFAULTS = {
    page_width:   215.9, # US Letter
    page_height:  279.4,
    label_width:   99.1, # Avery L7165-style sticker
    label_height:  67.7,
    columns:          2,
    rows:             4,
    margin_left:   8.85, # (215.9 - 2*99.1) / 2
    margin_top:     4.3, # (279.4 - 4*67.7) / 2
    gutter_x:       0.0,
    gutter_y:       0.0,
    start_offset:     0, # skip N already-used stickers on a part-used sheet
    offset_x:       0.0, # printer calibration nudge
    offset_y:       0.0,
    outlines:     false  # draw slot outlines for a plain-paper alignment test
  }.freeze

  def initialize(resources, scan_urls:, **options)
    @resources = resources
    @scan_urls = scan_urls
    @o = DEFAULTS.merge(options.compact)
  end

  def render
    document.render
  end

  # Exposed so tests can assert on page count / geometry without parsing a PDF.
  def document
    pdf = Prawn::Document.new(page_size: [mm(@o[:page_width]), mm(@o[:page_height])], margin: 0)
    draw_slot_outlines(pdf) if @o[:outlines]

    current_page = 0
    @resources.each_with_index do |resource, index|
      slot = @o[:start_offset].to_i + index
      page = slot / per_page

      if page > current_page
        (page - current_page).times { pdf.start_new_page }
        current_page = page
        draw_slot_outlines(pdf) if @o[:outlines]
      end

      x, y_top = slot_position(slot % per_page)
      LabelRenderer.new(resource, scan_url: @scan_urls[resource.id]).draw(
        pdf, x: x, y_top: y_top, width: mm(@o[:label_width]), height: mm(@o[:label_height])
      )
    end

    pdf
  end

  # How many sheets a given number of labels needs, honouring the start offset.
  def self.sheets_needed(count, columns:, rows:, start_offset: 0)
    per_page = [columns.to_i * rows.to_i, 1].max
    return 0 if count.zero?
    ((start_offset.to_i + count) / per_page.to_f).ceil
  end

  private

  def per_page
    @per_page ||= [@o[:columns].to_i * @o[:rows].to_i, 1].max
  end

  # Top-left corner of a slot, in Prawn points (y measured up from page bottom).
  def slot_position(position)
    row = position / @o[:columns].to_i
    col = position % @o[:columns].to_i

    x = mm(@o[:margin_left] + @o[:offset_x]) + col * mm(@o[:label_width] + @o[:gutter_x])
    y_from_top = mm(@o[:margin_top] + @o[:offset_y]) + row * mm(@o[:label_height] + @o[:gutter_y])

    [x, mm(@o[:page_height]) - y_from_top]
  end

  def draw_slot_outlines(pdf)
    pdf.stroke_color "CCCCCC"
    pdf.line_width 0.4
    per_page.times do |position|
      x, y_top = slot_position(position)
      pdf.stroke_rectangle([x, y_top], mm(@o[:label_width]), mm(@o[:label_height]))
    end
    pdf.stroke_color "000000"
  end

  def mm(value) = LabelRenderer.mm(value)
end
