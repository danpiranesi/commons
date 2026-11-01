# A single vehicle label on its own A6 page, for one-off printing from a
# vehicle's admin page. The label itself is drawn by LabelRenderer, which is
# shared with LabelSheetPdf so a single label and a sheet label look identical.
#
# Usage:
#   pdf = LabelPdf.new(resource, scan_url: vehicle_scan_url(resource.qr_token)).render
#   send_data pdf, type: "application/pdf", filename: "label.pdf"
class LabelPdf
  PAGE_WIDTH  = 105 # mm, A6
  PAGE_HEIGHT = 148 # mm, A6

  def initialize(resource, scan_url:)
    @resource = resource
    @scan_url = scan_url
  end

  def render
    pdf = Prawn::Document.new(
      page_size:   [mm(PAGE_WIDTH), mm(PAGE_HEIGHT)],
      page_layout: :portrait,
      margin:      0
    )

    LabelRenderer.new(@resource, scan_url: @scan_url).draw(
      pdf,
      x:      0,
      y_top:  mm(PAGE_HEIGHT),
      width:  mm(PAGE_WIDTH),
      height: mm(PAGE_HEIGHT)
    )

    pdf.render
  end

  private

  def mm(value) = LabelRenderer.mm(value)
end
