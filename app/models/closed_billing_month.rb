class ClosedBillingMonth < ApplicationRecord
  validates :billing_month, presence: true, uniqueness: true,
                            format: { with: /\A\d{6}\z/, message: "must be YYYYMM" }

  def self.closed?(billing_month)
    exists?(billing_month: billing_month)
  end

  # Human-readable label for display, e.g. "Juli 2026"
  def self.label_for(yyyymm)
    return yyyymm if yyyymm.blank?
    date = Date.new(yyyymm[0..3].to_i, yyyymm[4..5].to_i, 1)
    I18n.l(date, format: "%B %Y")
  rescue ArgumentError
    yyyymm
  end
end
