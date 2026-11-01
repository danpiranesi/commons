require "csv"

module Admin
  class MonthlyOverviewController < BaseController
    before_action :set_billing_month

    def show
      @bookings       = returned_bookings
      @closed         = ClosedBillingMonth.closed?(@billing_month)
      @available_months = available_billing_months
      # A trip made on behalf of a group is billed to the group, not the driver.
      @user_totals    = build_user_totals(@bookings.reject(&:on_behalf_of_group?))
      @group_totals   = build_group_totals(@bookings.select(&:on_behalf_of_group?))
      @vehicle_totals = build_vehicle_totals(@bookings)
      # Per-member trip lists, alphabetical; group trips are listed under their group.
      @bookings_by_user  = @bookings.reject(&:on_behalf_of_group?).group_by(&:user)
                                    .sort_by { |u, _| u.name_sort_key }
      @bookings_by_group = @bookings.select(&:on_behalf_of_group?).group_by(&:billing_group_id)
    end

    def update_mileage
      booking = Booking.find(params[:booking_id])
      booking.update!(end_mileage: params[:end_mileage].to_i)
      redirect_to admin_monthly_overview_path(billing_month: params[:billing_month]),
                  notice: t("admin.monthly_overview.notices.mileage_updated", id: booking.id)
    end

    def close_month
      if ClosedBillingMonth.closed?(@billing_month)
        redirect_to admin_monthly_overview_path(billing_month: @billing_month),
                    alert: t("admin.monthly_overview.alerts.already_closed")
        return
      end

      ClosedBillingMonth.create!(billing_month: @billing_month)
      redirect_to admin_monthly_overview_path(billing_month: @billing_month),
                  notice: t("admin.monthly_overview.notices.month_closed",
                            month: ClosedBillingMonth.label_for(@billing_month))
    end

    # GET /admin/monthly_overview/export_csv?billing_month=202607&type=biler
    def export_csv
      type    = params[:type].presence_in(%w[biler cykler]) || "biler"
      # Only charges to a personal ledger are transferred from the member. Group
      # trips and invoiced people are settled through the kørsel sheet instead.
      bookings = returned_bookings.select { |b| car_billing?(b) == (type == "biler") && b.collected_via_ledger? }

      month_abbr = danish_month_abbr(@billing_month)
      description = type == "biler" ? "Kørsel bil #{month_abbr}." : "Kørsel el-cykel #{month_abbr}."

      user_totals = bookings.group_by(&:user).transform_values { |bs| bs.sum { |b| b.total_amount || 0 } }

      csv_data = CSV.generate(col_sep: ";") do |csv|
        user_totals.sort_by { |u, _| u.name_sort_key }.each do |user, total|
          next if total.zero?
          account = user.accounting_account.presence || "?"
          name    = user.accounting_name.presence || user.name
          csv << [
            Date.current.strftime("%d-%m-%Y"),
            "Kreditor",
            account,
            name,
            description,
            format("%.2f", total).tr(".", ",")   # Danish decimal format
          ]
        end
      end

      filename = "#{type}_#{@billing_month}.csv"
      send_data csv_data, filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
    end

    # GET /admin/monthly_overview/export_summary?billing_month=202606
    #
    # The monthly kørsel sheet: one block per billing category, with the double
    # rate and the state rate applied on top of the plain figures.
    def export_summary
      sheet = MonthlyKoerselSheet.new(@billing_month)
      xlsx  = MonthlyKoerselXlsx.new(sheet).render

      send_data xlsx, filename: "koersel_#{@billing_month}.xlsx",
                      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                      disposition: "attachment"
    end

    private

    # A booking should never be unattributable, but if one ever is, it lands in a
    # "?" bucket rather than being silently dropped from the totals.
    def member_label(user)
      user&.name.presence || "?"
    end

    # The sheet identifies a vehicle by its short code (port), not its display name.
    def vehicle_label(resource)
      resource.port.presence || resource.name
    end

    def danish_month_name(yyyymm)
      date = Date.new(yyyymm[0..3].to_i, yyyymm[4..5].to_i, 1)
      "#{I18n.l(date, format: '%B', locale: :da).downcase} #{date.year}"
    rescue ArgumentError
      yyyymm
    end

    def set_billing_month
      @billing_month = params[:billing_month].presence || default_billing_month
    end

    def default_billing_month
      Booking.where(status: "returned").where.not(billing_month: nil)
             .maximum(:billing_month) || Date.current.strftime("%Y%m")
    end

    def available_billing_months
      Booking.where(status: "returned").where.not(billing_month: nil)
             .distinct.pluck(:billing_month).sort.reverse
    end

    def returned_bookings
      Booking.where(status: "returned", billing_month: @billing_month)
             .includes({ user: :billing_category }, { billing_group: :billing_category }, resource: :resource_type)
             .order(:completed_at)
    end

    def build_user_totals(bookings)
      bookings.group_by(&:user).map do |user, bs|
        {
          user:   user,
          total:  bs.sum { |b| b.total_amount || 0 },
          km:     bs.sum { |b| b.km_driven || 0 },
          count:  bs.size
        }
      end.sort_by { |r| User.name_sort_key(r[:user]&.name) }
    end

    def build_group_totals(bookings)
      bookings.group_by(&:billing_group).map do |group, bs|
        {
          group:  group,
          total:  bs.sum { |b| b.total_amount || 0 },
          km:     bs.sum { |b| b.km_driven || 0 },
          count:  bs.size
        }
      end.sort_by { |r| User.name_sort_key(r[:group].name) }
    end

    def build_vehicle_totals(bookings)
      bookings.group_by(&:resource).map do |resource, bs|
        {
          resource: resource,
          total:    bs.sum { |b| b.total_amount || 0 },
          km:       bs.sum { |b| b.km_driven || 0 },
          count:    bs.size
        }
      end.sort_by { |r| r[:resource].display_name }
    end

    def car_billing?(booking)
      booking.resource.resource_type.billed_as_car?
    end

    def danish_month_abbr(yyyymm)
      date = Date.new(yyyymm[0..3].to_i, yyyymm[4..5].to_i, 1)
      I18n.l(date, format: "%b", locale: :da).downcase
    rescue ArgumentError
      yyyymm
    end
  end
end
