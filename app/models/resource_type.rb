class ResourceType < ApplicationRecord
  BILLING_TYPES = %w[per_day_and_km per_day free].freeze

  has_many :resources, dependent: :restrict_with_error

  validates :name, presence: true
  validates :billing_type, presence: true, inclusion: { in: BILLING_TYPES }

  scope :ordered, -> { order(:sort_order, :name) }
  # Types that keep their own lifecycle rules (everything that doesn't defer to the
  # car). Drives the Rules page's type switcher.
  scope :with_own_rules, -> { where(inherit_rules_from_car: false) }

  # The canonical car type — the source of truth for rules that other types
  # inherit. Prefer the one named "Car"; fall back to any mileage-tracked type.
  def self.car
    find_by(name: "Car") || where(billing_type: "per_day_and_km").order(:sort_order, :id).first
  end
  # Types that carry a default hourly rate (everything a member books; tolls are
  # priced per crossing, not per hour).
  scope :priceable, -> { where.not(name: "Toll").ordered }

  DEFAULT_HOUR_RATE = 5.0

  def tracks_mileage?
    billing_type == "per_day_and_km"
  end

  # Whether trips on this type belong in the car column of the monthly sheet.
  # Cars themselves, plus everything that exists only to be hitched to one — a
  # trailer, a rocket box, a bridge crossing. That income is car income: BB
  # weighs it against the cost of running the cars, not the bicycles.
  def billed_as_car?
    tracks_mileage? || inherit_rules_from_car?
  end

  # The default per-hour rate for this type and user type, which resources
  # inherit unless they set their own price. nil for a type with no default.
  def default_hour_rate_for(user_type)
    rate = default_hour_rates.presence&.[](user_type.to_s)
    rate.nil? ? nil : BigDecimal(rate.to_s)
  end

  # Seed 5 kr/hour for every user type on every priceable type, without
  # overwriting a rate an admin has already changed.
  def self.seed_default_rates!
    priceable.find_each do |type|
      rates = type.default_hour_rates || {}
      User::USER_TYPES.each { |ut| rates[ut] ||= DEFAULT_HOUR_RATE.to_s }
      type.update_column(:default_hour_rates, rates)
    end
  end
end
