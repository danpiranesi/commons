# The monthly summary sheet as a spreadsheet. xlsx rather than CSV because
# semicolon-separated files with Danish decimal commas open inconsistently across
# spreadsheet apps; real columns and numbers open the same way everywhere.
#
#   Månedlig total
#   biler, juni 2026
#
#   Bruger              Km      Beløb
#   ...                            ...
#   I alt             1.234   5.678,00
#
#   Bil                 Km      Beløb
#   ...                            ...
#   I alt             1.234   5.678,00
class MonthlySummaryXlsx
  def initialize(type:, month_label:, users:, vehicles:, total_km:, total_amount:)
    @type         = type
    @month_label  = month_label
    @users        = users
    @vehicles     = vehicles
    @total_km     = total_km
    @total_amount = total_amount
  end

  def render
    package = Axlsx::Package.new
    workbook = package.workbook
    s = styles(workbook)

    workbook.add_worksheet(name: "Summering") do |sheet|
      sheet.add_row ["Månedlig total"], style: [s[:title]]
      sheet.add_row ["#{@type}, #{@month_label}"], style: [s[:subtitle]]
      sheet.add_row []

      add_table(sheet, s, "Bruger", @users)
      sheet.add_row []
      add_table(sheet, s, "Bil", @vehicles)

      sheet.column_widths 28, 12, 14
    end

    package.to_stream.read
  end

  private

  # Each table is a header row, the rows themselves, then a bold "I alt" line
  # carrying the same totals, so the two tables visibly reconcile.
  def add_table(sheet, s, label, rows)
    sheet.add_row [label, "Km", "Beløb"], style: [s[:header], s[:header_r], s[:header_r]]
    rows.each do |row|
      sheet.add_row [row[:label], row[:km], row[:amount]], style: [s[:text], s[:km], s[:money]]
    end
    sheet.add_row ["I alt", @total_km, @total_amount],
                  style: [s[:total_text], s[:total_km], s[:total_money]]
  end

  def styles(workbook)
    st = workbook.styles
    thin_top = { style: :thin, color: "000000", edges: [:top] }
    thin_bottom = { style: :thin, color: "000000", edges: [:bottom] }

    {
      title:       st.add_style(b: true, sz: 14),
      subtitle:    st.add_style(b: true, sz: 12),
      header:      st.add_style(b: true, border: thin_bottom),
      header_r:    st.add_style(b: true, alignment: { horizontal: :right }, border: thin_bottom),
      text:        st.add_style({}),
      km:          st.add_style(format_code: "#,##0",    alignment: { horizontal: :right }),
      money:       st.add_style(format_code: "#,##0.00", alignment: { horizontal: :right }),
      total_text:  st.add_style(b: true, border: thin_top),
      total_km:    st.add_style(b: true, format_code: "#,##0",    alignment: { horizontal: :right }, border: thin_top),
      total_money: st.add_style(b: true, format_code: "#,##0.00", alignment: { horizontal: :right }, border: thin_top)
    }
  end
end
