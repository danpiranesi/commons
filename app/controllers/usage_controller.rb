require "csv"

# A member's own booking history: their completed (billed) trips grouped by month,
# with per-month totals and a CSV export. Read entirely from live data and scoped
# to current_user, so it always reflects the latest bookings and never leaks
# another member's history.
class UsageController < ApplicationController
  def show
    @bookings_by_month = current_user.bookings
                                     .where(status: "returned").where.not(billing_month: nil)
                                     .includes(:billing_group, resource: :resource_type)
                                     .order(completed_at: :desc, start_at: :desc)
                                     .group_by(&:billing_month)
    @months = @bookings_by_month.keys.sort.reverse

    respond_to do |format|
      format.html
      format.csv do
        send_data build_csv,
                  filename: "bookinger-#{Date.current.strftime('%Y%m%d')}.csv",
                  type: "text/csv"
      end
    end
  end

  private

  def build_csv
    CSV.generate(col_sep: ";") do |csv|
      csv << [
        t("usage.csv.month"), t("usage.csv.date"), t("usage.csv.resource"),
        t("usage.csv.hours"), t("usage.csv.km"), t("usage.csv.cost")
      ]
      @months.each do |month|
        @bookings_by_month[month].each do |b|
          csv << [
            ClosedBillingMonth.label_for(month),
            (b.completed_at || b.start_at)&.strftime("%Y-%m-%d"),
            b.resource.display_name,
            b.billed_hours,
            b.km_driven,
            format("%.2f", b.total_amount || 0).tr(".", ",") # Danish decimal
          ]
        end
      end
    end
  end

end
