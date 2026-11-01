# Draws ONE vehicle label into an arbitrary box on a Prawn document.
#
# Shared by LabelPdf (a single A6 label) and LabelSheetPdf (many labels laid out
# on a sticker sheet), so the two can never drift apart.
#
# Layout adapts to the box's shape:
#   landscape (wider than tall, e.g. 99.1 × 67.7 mm sticker) → QR left, text right
#   portrait  (taller than wide, e.g. A6)                    → text top, QR beneath
#
# Content is: vehicle name, then the numbered how-to steps. The scan URL is
# deliberately NOT printed — the QR is the way in, and the text is the room.
#
# Everything is positioned absolutely (no cursor), because on a sheet each label
# sits at a computed x/y — content must never bleed into a neighbouring sticker.
class LabelRenderer
  PT_PER_MM = 72.0 / 25.4

  # Keep content this far inside the die-cut edge so slight printer
  # misalignment never clips the QR or text.
  INSET_MM = 4

  # Fallback if the locale file is missing; the sticker is always Danish.
  DEFAULT_STEPS = [
    "Book på booking.example.org",
    "Scan QR og indtast km-stand for at starte",
    "God tur!",
    "Scan igen og indtast km-stand, når bilen er tilbage på pladsen"
  ].freeze

  def self.mm(value) = value * PT_PER_MM

  def initialize(resource, scan_url:)
    @resource = resource
    @scan_url = scan_url
  end

  # x / y_top are the box's top-left corner in Prawn points (y measured up from
  # the page bottom). width / height are in points.
  def draw(pdf, x:, y_top:, width:, height:)
    inset = mm(INSET_MM)
    cx = x + inset
    cy = y_top - inset
    cw = width  - 2 * inset
    ch = height - 2 * inset
    return if cw <= 0 || ch <= 0

    if cw > ch
      draw_landscape(pdf, cx, cy, cw, ch)
    else
      draw_portrait(pdf, cx, cy, cw, ch)
    end
    pdf.fill_color "000000"
  end

  private

  # QR on the left (vertically centred), name + steps on the right.
  def draw_landscape(pdf, x, y_top, w, h)
    gap     = mm(4)
    qr_size = [h, w * 0.42].min
    draw_qr(pdf, x: x, top_y: y_top - (h - qr_size) / 2.0, size: qr_size)

    tx = x + qr_size + gap
    tw = w - qr_size - gap
    return if tw <= 0

    bottom = y_top - h
    cursor = y_top

    pdf.fill_color "888880"
    pdf.text_box "COMMONS", at: [tx, cursor], width: tw, height: mm(3.5),
                 size: 6, character_spacing: 1.2
    cursor -= mm(4.5)

    pdf.fill_color "000000"
    pdf.font("Helvetica-Bold")
    pdf.text_box safe(@resource.display_name), at: [tx, cursor], width: tw, height: mm(11),
                 size: 12, leading: 1, overflow: :shrink_to_fit, min_font_size: 8
    pdf.font("Helvetica")
    cursor -= mm(12)

    if @resource.license_number.present?
      pdf.fill_color "666666"
      pdf.text_box safe(@resource.license_number), at: [tx, cursor], width: tw, height: mm(4), size: 7.5
      cursor -= mm(5)
    end

    # Numbered steps, directly under the title, a little smaller than it.
    pdf.fill_color "222222"
    pdf.text_box steps_text, at: [tx, cursor], width: tw, height: [cursor - bottom, mm(4)].max,
                 size: 9, leading: 2, overflow: :shrink_to_fit, min_font_size: 5
  end

  # Name + steps on top, QR filling whatever space is left beneath.
  def draw_portrait(pdf, x, y_top, w, h)
    bottom = y_top - h
    cursor = y_top

    pdf.fill_color "888880"
    pdf.text_box "COMMONS", at: [x, cursor], width: w, height: mm(4),
                 size: 7, character_spacing: 1.5
    cursor -= mm(5.5)

    pdf.fill_color "000000"
    pdf.font("Helvetica-Bold")
    pdf.text_box safe(@resource.display_name), at: [x, cursor], width: w, height: mm(13),
                 size: 15, leading: 2, overflow: :shrink_to_fit, min_font_size: 9
    pdf.font("Helvetica")
    cursor -= mm(14)

    if @resource.license_number.present?
      pdf.fill_color "666666"
      pdf.text_box safe(@resource.license_number), at: [x, cursor], width: w, height: mm(5), size: 9
      cursor -= mm(6)
    end

    steps_height = mm(26)
    pdf.fill_color "222222"
    pdf.text_box steps_text, at: [x, cursor], width: w, height: steps_height,
                 size: 10, leading: 2.5, overflow: :shrink_to_fit, min_font_size: 6
    cursor -= steps_height + mm(3)

    qr_size = [w, cursor - bottom].min
    return unless qr_size > mm(12)
    draw_qr(pdf, x: x + (w - qr_size) / 2.0, top_y: cursor, size: qr_size)
  end

  # QR as a grid of filled rectangles (no image dependency).
  def draw_qr(pdf, x:, top_y:, size:)
    matrix = RQRCode::QRCode.new(@scan_url, level: :m).modules
    cell   = size.to_f / matrix.size

    pdf.fill_color "000000"
    matrix.each_with_index do |row, row_idx|
      row.each_with_index do |dark, col_idx|
        next unless dark
        pdf.fill_rectangle([x + col_idx * cell, top_y - row_idx * cell], cell, cell)
      end
    end
  end

  # Always Danish — the sticker lives on a car at Commons, regardless of which
  # locale the admin who printed it happens to use.
  def steps_text
    steps = I18n.t("labels.steps", locale: :da, default: nil)
    steps = DEFAULT_STEPS unless steps.is_a?(Array) && steps.any?
    safe(steps.each_with_index.map { |step, i| "#{i + 1}.  #{step}" }.join("\n"))
  end

  # Prawn's built-in fonts only cover Windows-1252 and *raise* on anything else.
  # Danish (å æ ø) is fine, but a stray curly quote or emoji in a vehicle name
  # would otherwise blow up a whole sheet — drop those characters instead.
  def safe(text)
    text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "").encode("UTF-8")
  end

  def mm(value) = self.class.mm(value)
end
