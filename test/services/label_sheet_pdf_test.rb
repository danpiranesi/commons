require "test_helper"

class LabelSheetPdfTest < ActiveSupport::TestCase
  def make_cars(count)
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    Array.new(count) do |i|
      Resource.create!(name: "Car #{i}", status: "active", resource_type: rt,
                       port: "A-0#{i}", color: "Blue", make: "VW")
    end
  end

  def urls_for(resources)
    resources.index_by(&:id).transform_values { |r| "https://booking.example.org/v/#{r.qr_token}" }
  end

  def sheet(resources, **opts)
    LabelSheetPdf.new(resources, scan_urls: urls_for(resources), **opts)
  end

  test "defaults to US Letter with 8 labels per sheet" do
    cars = make_cars(5)
    doc  = sheet(cars).document

    # US Letter = 612 × 792 pt
    assert_in_delta 612, doc.page.dimensions[2], 0.5
    assert_in_delta 792, doc.page.dimensions[3], 0.5
    assert_equal 1, doc.page_count, "5 labels fit on one 2x4 sheet"
  end

  test "paginates past the 8th label" do
    assert_equal 1, sheet(make_cars(8)).document.page_count
    assert_equal 2, sheet(make_cars(9)).document.page_count
  end

  test "start_offset consumes slots so a part-used sheet spills to a second page" do
    cars = make_cars(4)
    # 6 already used + 4 more = 10 slots → 2 sheets
    assert_equal 2, sheet(cars, start_offset: 6).document.page_count
  end

  test "sheets_needed math honours the start offset" do
    assert_equal 0, LabelSheetPdf.sheets_needed(0, columns: 2, rows: 4)
    assert_equal 1, LabelSheetPdf.sheets_needed(8, columns: 2, rows: 4)
    assert_equal 2, LabelSheetPdf.sheets_needed(9, columns: 2, rows: 4)
    assert_equal 2, LabelSheetPdf.sheets_needed(4, columns: 2, rows: 4, start_offset: 6)
  end

  test "every dimension is adjustable (A4, 3 across)" do
    cars = make_cars(3)
    doc  = sheet(cars, page_width: 210, page_height: 297, columns: 3, rows: 8,
                 label_width: 70, label_height: 37).document

    assert_in_delta 595.3, doc.page.dimensions[2], 1.0 # A4 width in pt
    assert_in_delta 841.9, doc.page.dimensions[3], 1.0 # A4 height in pt
    assert_equal 1, doc.page_count
  end

  test "a name with characters outside Prawn's built-in font range doesn't kill the sheet" do
    rt = ResourceType.create!(name: "T-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
    odd = Resource.create!(name: "Bilen 🚗 “Blå” — Peugeot", status: "active",
                           resource_type: rt, license_number: "AB 12 345")

    pdf = sheet([odd]).render
    assert pdf.start_with?("%PDF"), "unsupported characters should be dropped, not raise"
  end

  test "the printed label does not include the scan URL" do
    cars = make_cars(1)
    # The QR encodes the URL; the sticker text must not repeat it.
    renderer = LabelRenderer.new(cars.first, scan_url: "https://booking.example.org/v/TOKEN123")
    drawn = []
    fake = Object.new
    fake.define_singleton_method(:text_box) { |text, **| drawn << text }
    fake.define_singleton_method(:fill_color) { |*| }
    fake.define_singleton_method(:font) { |*| }
    fake.define_singleton_method(:fill_rectangle) { |*| }
    renderer.draw(fake, x: 0, y_top: LabelRenderer.mm(67.7), width: LabelRenderer.mm(99.1), height: LabelRenderer.mm(67.7))

    assert drawn.none? { |t| t.to_s.include?("TOKEN123") }, "scan URL must not be printed"
    assert drawn.any? { |t| t.to_s.include?("booking.example.org") }, "step 1 mentions the booking site"
    assert drawn.any? { |t| t.to_s.include?("God tur!") }, "steps are in Danish"
  end

  test "renders a non-trivial PDF for the real sticker size" do
    cars = make_cars(2)
    pdf  = sheet(cars).render
    assert pdf.start_with?("%PDF"), "should be a PDF"
    assert pdf.bytesize > 5_000, "should contain QR artwork"
  end
end
