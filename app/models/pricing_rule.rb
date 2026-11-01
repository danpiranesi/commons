class PricingRule < ApplicationRecord
  belongs_to :resource

  validates :multiplier, presence: true, numericality: { greater_than: 0 }
  validates :min_days, numericality: { greater_than: 0, allow_nil: true }
  validates :max_days, numericality: { greater_than: 0, allow_nil: true }
end
