# The monthly kørsel sheet: one block per billing category, each with the
# columns that category needs.
#
#   §1 Medlemmer i FØ              normal rate, bank transfer
#   §2 HP-ordninger                normal rate, invoice
#   §3 Koll. grupper / ikke i FØ   base and doubled shown side by side
#   §4 K/S arbejdsgrupper          km at the state rate
#   §5 Bæredygtig befordring       normal rate
class MonthlyKoerselSheet
  Row = Struct.new(:label, :status, :cykler, :biler, :km, :charged_cykler, :charged_biler,
                   keyword_init: true)

  SECTION_TITLES = {
    1 => "Medlemmer i fælles økonomi",
    2 => "Personer på HP-ordninger, som skal have regning",
    3 => "Koll. grupper og personer ikke i FØ betaler dobbelt takst",
    4 => "K/S arbejdsgrupper betaler statens takst",
    5 => "Bæredygtig befordring"
  }.freeze

  def initialize(billing_month)
    @billing_month = billing_month
  end

  def month_label
    date = Date.new(@billing_month[0..3].to_i, @billing_month[4..5].to_i, 1)
    "#{I18n.l(date, format: '%B', locale: :da).downcase} #{date.year}"
  rescue ArgumentError
    @billing_month
  end

  # { section_number => [Row, ...] }. Reports what was actually charged
  # (total_amount), with the pre-rate base recovered from the frozen billing_rate.
  def sections
    @sections ||= begin
      grouped = Hash.new { |h, k| h[k] = [] }

      bookings.group_by { |b| [effective_category(b), b.billed_to] }
              .each do |(category, label), group|
        grouped[category.section] << Row.new(
          label:          label,
          status:         category.name_da,
          cykler:         group.reject { |b| car?(b) }.sum { |b| base_of(b) },
          biler:          group.select { |b| car?(b) }.sum { |b| base_of(b) },
          km:             group.sum { |b| b.km_driven || 0 },
          charged_cykler: group.reject { |b| car?(b) }.sum { |b| b.total_amount || 0 },
          charged_biler:  group.select { |b| car?(b) }.sum { |b| b.total_amount || 0 }
        )
      end

      grouped.each_value { |rows| rows.sort_by! { |r| r.label.to_s.downcase } }
      grouped
    end
  end

  def section_total(section, field)
    (sections[section] || []).sum { |row| row.public_send(field) || 0 }
  end

  # Grand totals of the pre-rate base, which reconcile against the plain
  # per-resource figures, the check the bookkeeper relies on.
  def total_cykler = bookings.reject { |b| car?(b) }.sum { |b| base_of(b) }
  def total_biler  = bookings.select { |b| car?(b) }.sum { |b| base_of(b) }

  # Trips whose person has no category yet fall back to Medlem, so the sheet
  # still balances. They are counted here so the gap stays visible.
  def uncategorised_count
    bookings.count { |b| b.effective_billing_category.nil? }
  end

  # ── Member bank-transfer rows ─────────────────────────────────
  # One row per person per vehicle type, in the shape the bookkeeper posts to the
  # bank: a Kreditor line carrying their konto and the charged amount. A person
  # running a business gets separate firm rows, deliberately keyed to the same
  # (private) konto so the deduction from their salary is visible.
  BankRow = Struct.new(:konto, :navn, :tekst, :debet, :type, :firm, keyword_init: true)

  def bank_rows
    @bank_rows ||= member_bookings
                   .group_by { |b| [b.user, firm_group(b), car?(b)] }
                   .map do |(user, firm, is_car), group|
                     BankRow.new(
                       konto: user&.accounting_account.presence || "?",
                       navn:  bank_name_for(user, firm),
                       tekst: "#{is_car ? 'Kørsel bil' : 'Kørsel el-cykel'} #{month_abbr}.",
                       debet: group.sum { |b| b.total_amount || 0 },
                       type:  is_car ? "bil" : "cykel",
                       firm:  firm.present?
                     )
                   end
                   .reject { |r| r.debet.zero? }
                   .sort_by { |r| [r.navn.to_s.downcase, r.type] }
  end

  # Cars and bicycles are posted on their own sheets, each balancing to its own
  # Finans line: BB compares each vehicle group's income against that group's
  # costs, which a combined sheet can't show.
  def bank_rows_for(type) = bank_rows.select { |r| r.type == type }
  def bank_total_for(type) = bank_rows_for(type).sum(&:debet)

  def bank_total = bank_rows.sum(&:debet)

  # The balancing Finans account the bank-transfer sheet posts to (admin-editable).
  def finance_account = SiteSetting.instance.finance_account.presence || "2400"

  # The single line the master sheet shows in place of the individual members.
  def member_line_total(field)
    rows = member_bookings.reject { |b| firm_group(b) }
    case field
    when :cykler then rows.reject { |b| car?(b) }.sum { |b| base_of(b) }
    when :biler  then rows.select { |b| car?(b) }.sum { |b| base_of(b) }
    end
  end

  # Named firm lines still print on the master, with the person's private konto.
  def firm_rows
    bank_rows.select(&:firm)
  end

  def month_abbr
    date = Date.new(@billing_month[0..3].to_i, @billing_month[4..5].to_i, 1)
    I18n.l(date, format: "%b", locale: :da).downcase.delete(".")
  rescue ArgumentError
    @billing_month
  end

  private

  # Everything that belongs on the bank-transfer sheets: personal trips by
  # someone in the member category, plus their business trips.
  def member_bookings
    @member_bookings ||= bookings.select do |b|
      firm_group(b) || (b.billing_group_id.nil? && member_category?(b.user))
    end
  end

  def member_category?(user)
    key = user&.billing_category&.key
    key.nil? || key == "member" # uncategorised falls back to Medlem, as elsewhere
  end

  # A booking made on behalf of a personligt-erhverv group is a firm trip.
  def firm_group(booking)
    group = booking.billing_group
    group if group&.billing_category&.key == "personligt_erhverv"
  end

  def bank_name_for(user, firm)
    base = user&.accounting_name.presence || user&.name.presence || "?"
    firm ? "#{base} (#{firm.name})" : base
  end

  def bookings
    @bookings ||= Booking.where(status: "returned", billing_month: @billing_month)
                         .includes(:user, :billing_group, resource: :resource_type)
                         .to_a
  end

  # Stands in for a missing category so the sheet can always be produced, even
  # before anyone has been categorised. Charges at the plain recorded amount and
  # says so in the status column, rather than quietly claiming to be Medlem.
  UNCATEGORISED = Struct.new(:section, :name_da) do
    def charge_for(normal_amount:, km:) = normal_amount
  end.new(1, "Ikke kategoriseret").freeze

  def effective_category(booking)
    booking.effective_billing_category || BillingCategory.default || UNCATEGORISED
  end

  # The charge before its rate was applied. Falls back to the charged amount for
  # trips completed before rates were stored (there the two are the same).
  def base_of(booking)
    booking.billing_rate_struct&.base || booking.total_amount || 0
  end

  # Cars, and the things that only move because a car is pulling them.
  def car?(booking)
    booking.resource.resource_type.billed_as_car?
  end
end
