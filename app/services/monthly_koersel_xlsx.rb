# Renders MonthlyKoerselSheet as a real spreadsheet, one block per category,
# each with the columns that block needs. Numbers are written as numbers so the
# bookkeeper can keep working in the file.
class MonthlyKoerselXlsx
  def initialize(sheet)
    @sheet = sheet
  end

  def render
    package = Axlsx::Package.new
    workbook = package.workbook
    s = styles(workbook)

    workbook.add_worksheet(name: "Kørsel") do |ws|
      ws.add_row ["Kørsel #{@sheet.month_label}"], style: [s[:title]]
      ws.add_row []

      section_1(ws, s)
      section_2(ws, s)
      section_3(ws, s)
      section_4(ws, s)
      section_5(ws, s)
      grand_total(ws, s)

      ws.column_widths 34, 14, 14, 14, 14, 18
    end

    member_sheets(workbook, s)

    package.to_stream.read
  end

  private

  def rows_for(n) = @sheet.sections[n] || []

  def heading(ws, s, number)
    ws.add_row [MonthlyKoerselSheet::SECTION_TITLES[number]], style: [s[:heading]]
  end

  # Members: collected by bank transfer, so the master only carries the total —
  # the individuals behind it are itemised on the bank-transfer sheets. Firm
  # (personligt erhverv) lines stay named here, against the person's private
  # konto, so the salary deduction is visible on the master.
  def section_1(ws, s)
    heading(ws, s, 1)
    ws.add_row ["Navn", "Cykler", "Biler"], style: [s[:th], s[:th_r], s[:th_r]]
    ws.add_row ["Medlemmer i FØ (se arket »Medlemmer«)",
                @sheet.member_line_total(:cykler), @sheet.member_line_total(:biler)],
               style: [s[:td], s[:kr], s[:kr]]

    @sheet.firm_rows.each do |r|
      ws.add_row ["#{r.navn} — konto #{r.konto}",
                  (r.type == "cykel" ? r.debet : nil),
                  (r.type == "bil" ? r.debet : nil)],
                 style: [s[:td], s[:kr], s[:kr]]
    end

    ws.add_row ["I alt", @sheet.section_total(1, :cykler), @sheet.section_total(1, :biler)],
               style: [s[:tot], s[:tot_kr], s[:tot_kr]]
    ws.add_row []
  end

  # Bank-transfer sheets — one per vehicle group. Cars and bicycles are kept
  # apart, each balancing to its own Finans line, so BB can hold each group's
  # income against that group's costs and judge whether the prices are right.
  def member_sheets(workbook, s)
    { "bil" => "Biler", "cykel" => "Cykler" }.each do |type, label|
      bank_sheet(workbook, s, type: type, name: "#{label} #{@sheet.month_abbr}")
    end
  end

  def bank_sheet(workbook, s, type:, name:)
    rows  = @sheet.bank_rows_for(type)
    total = @sheet.bank_total_for(type)

    workbook.add_worksheet(name: name) do |ws|
      ws.add_row ["Bogføringsdato", "Bilag", "Kontotype", "Konto", "Navn", "Tekst",
                  "Debet", "Kredit", "Forfaldsdato"],
                 style: [s[:th], s[:th], s[:th], s[:th], s[:th], s[:th], s[:th_r], s[:th_r], s[:th]]

      rows.each do |r|
        ws.add_row [nil, nil, "Kreditor", r.konto, r.navn, r.tekst, r.debet, nil, nil],
                   style: [s[:td], s[:td], s[:td], s[:td], s[:td], s[:td], s[:kr], s[:kr], s[:td]]
      end

      ws.add_row [nil, nil, "Finans", @sheet.finance_account, nil, nil, nil, total, nil],
                 style: [s[:td], s[:td], s[:tot], s[:tot], s[:td], s[:td], s[:tot_kr], s[:tot_kr], s[:td]]
      ws.add_row [nil, nil, "tjek", nil, nil, nil, total, total, nil],
                 style: [s[:td], s[:td], s[:check], s[:td], s[:td], s[:td], s[:check_kr], s[:check_kr], s[:td]]
      ws.add_row [nil, nil, "før regulering", nil, nil, nil, total, nil, nil],
                 style: [s[:td], s[:td], s[:td], s[:td], s[:td], s[:td], s[:kr], s[:td], s[:td]]

      ws.column_widths 16, 10, 12, 10, 26, 22, 12, 12, 14
    end
  end

  # HP: normal rate, but invoiced rather than taken by bank transfer.
  def section_2(ws, s)
    heading(ws, s, 2)
    ws.add_row ["Navn", "Cykler", "Biler", "status"], style: [s[:th], s[:th_r], s[:th_r], s[:th]]
    rows_for(2).each { |r| ws.add_row [r.label, r.cykler, r.biler, r.status], style: [s[:td], s[:kr], s[:kr], s[:td]] }
    ws.add_row ["Regninger i alt", @sheet.section_total(2, :cykler), @sheet.section_total(2, :biler)],
               style: [s[:tot], s[:tot_kr], s[:tot_kr]]
    ws.add_row []
  end

  # Double rate: base and charged shown side by side.
  def section_3(ws, s)
    heading(ws, s, 3)
    ws.add_row ["Navn", "cykler", "dobbelt takst", "biler", "dobbelt takst", "status"],
               style: [s[:th], s[:th_r], s[:th_r], s[:th_r], s[:th_r], s[:th]]
    rows_for(3).each do |r|
      ws.add_row [r.label, r.cykler, r.charged_cykler, r.biler, r.charged_biler, r.status],
                 style: [s[:td], s[:kr], s[:kr], s[:kr], s[:kr], s[:td]]
    end
    ws.add_row ["Opgørelser i alt", @sheet.section_total(3, :cykler), nil, @sheet.section_total(3, :biler)],
               style: [s[:tot], s[:tot_kr], s[:tot], s[:tot_kr]]
    ws.add_row ["Opkræves i alt", nil, @sheet.section_total(3, :charged_cykler), nil, @sheet.section_total(3, :charged_biler)],
               style: [s[:tot], s[:tot], s[:tot_kr], s[:tot], s[:tot_kr]]
    ws.add_row []
  end

  # Work groups: km at the state rate, which replaces the normal amount.
  def section_4(ws, s)
    heading(ws, s, 4)
    ws.add_row ["Navn", "Biler", "km", "statens takst"], style: [s[:th], s[:th_r], s[:th_r], s[:th_r]]
    rows_for(4).each { |r| ws.add_row [r.label, r.biler, r.km, r.charged_biler], style: [s[:td], s[:kr], s[:km], s[:kr]] }
    ws.add_row ["I alt", @sheet.section_total(4, :biler), @sheet.section_total(4, :km), @sheet.section_total(4, :charged_biler)],
               style: [s[:tot], s[:tot_kr], s[:tot_km], s[:tot_kr]]
    ws.add_row []
  end

  def section_5(ws, s)
    heading(ws, s, 5)
    ws.add_row ["Navn", "Cykler", "Biler"], style: [s[:th], s[:th_r], s[:th_r]]
    rows_for(5).each { |r| ws.add_row [r.label, r.cykler, r.biler], style: [s[:td], s[:kr], s[:kr]] }
    ws.add_row ["BB i alt", @sheet.section_total(5, :cykler), @sheet.section_total(5, :biler)],
               style: [s[:tot], s[:tot_kr], s[:tot_kr]]
    ws.add_row []
  end

  def grand_total(ws, s)
    ws.add_row ["", "cykler", "biler"], style: [s[:td], s[:th_r], s[:th_r]]
    ws.add_row ["I alt sammentalt herover", @sheet.total_cykler, @sheet.total_biler],
               style: [s[:tot], s[:tot_kr], s[:tot_kr]]

    if @sheet.uncategorised_count.positive?
      ws.add_row []
      ws.add_row ["Bemærk: #{@sheet.uncategorised_count} ture mangler en takstkategori og er regnet som Medlem."],
                 style: [s[:note]]
    end
  end

  def styles(wb)
    st = wb.styles
    top    = { style: :thin, color: "000000", edges: [:top] }
    bottom = { style: :thin, color: "000000", edges: [:bottom] }
    {
      title:   st.add_style(b: true, sz: 15),
      heading: st.add_style(b: true, sz: 11, bg_color: "EFEEEA"),
      th:      st.add_style(b: true, border: bottom),
      th_r:    st.add_style(b: true, border: bottom, alignment: { horizontal: :right }),
      td:      st.add_style({}),
      kr:      st.add_style(format_code: "#,##0.00", alignment: { horizontal: :right }),
      km:      st.add_style(format_code: "#,##0",    alignment: { horizontal: :right }),
      tot:     st.add_style(b: true, border: top),
      tot_kr:  st.add_style(b: true, border: top, format_code: "#,##0.00", alignment: { horizontal: :right }),
      tot_km:  st.add_style(b: true, border: top, format_code: "#,##0",    alignment: { horizontal: :right }),
      note:    st.add_style(i: true, fg_color: "888880"),
      # The bookkeeper's green check row.
      check:    st.add_style(b: true, bg_color: "D9EAD3", border: top),
      check_kr: st.add_style(b: true, bg_color: "D9EAD3", border: top,
                             format_code: "#,##0.00", alignment: { horizontal: :right })
    }
  end
end
