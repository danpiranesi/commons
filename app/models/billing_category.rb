# How a trip is charged, and which block of the monthly accounting sheet it
# prints in. The rule lives here rather than on each person, so an admin picks
# "interessegruppe" and the double rate follows automatically.
#
# Two rate modes cover every rule on the sheet:
#
#   multiplier  charge = normal price x rate_value   (x1 normal, x2 double)
#   per_km      charge = km x rate_value             (the state's rate, which
#                                                     replaces the calculation)
class BillingCategory < ApplicationRecord
  RATE_MODES  = %w[multiplier per_km].freeze
  COLLECTIONS = %w[bank invoice internal].freeze

  has_many :users, dependent: :nullify
  has_many :billing_groups, dependent: :restrict_with_error

  validates :key, presence: true, uniqueness: true
  validates :name_da, presence: true
  validates :rate_mode, inclusion: { in: RATE_MODES }
  validates :collection, inclusion: { in: COLLECTIONS }
  validates :rate_value, numericality: { greater_than_or_equal_to: 0 }
  validates :section, numericality: { only_integer: true }

  scope :ordered,  -> { order(:section, :position, :name_da) }
  # Categories a person can be assigned; the rest describe groups.
  scope :personal, -> { where(personal: true).ordered }

  # Categories seeded on setup.
  # key, name_da, section, rate_mode, rate_value, collection, personal
  DEFAULTS = [
    %w[member]             + ["Medlem",                 1, "multiplier", 1.0,  "bank",     true],
    %w[hp]                 + ["HP-ordning",             2, "multiplier", 1.0,  "invoice",  true],
    %w[ansat_lejer]        + ["ansat/lejer",            3, "multiplier", 2.0,  "invoice",  true],
    %w[perma]              + ["perma",                  3, "multiplier", 2.0,  "invoice",  true],
    %w[interessegruppe]    + ["interessegr.",           3, "multiplier", 2.0,  "invoice",  false],
    %w[servicegruppe]      + ["servicegr",              3, "multiplier", 2.0,  "invoice",  false],
    %w[ks_arbejdsgruppe]   + ["K/S arbejdsgruppe",      4, "per_km",     3.94, "internal", false],
    %w[bb]                 + ["Bæredygtig befordring",  5, "multiplier", 1.0,  "internal", false],
    %w[personligt_erhverv] + ["Personligt erhverv",     1, "multiplier", 1.0,  "invoice",  true]
  ].freeze

  def self.seed_defaults!
    DEFAULTS.each_with_index do |(key, name_da, section, rate_mode, rate_value, collection, personal), i|
      category = find_or_initialize_by(key: key)
      category.assign_attributes(name_da: name_da, section: section, rate_mode: rate_mode,
                                 collection: collection, personal: personal, position: i)
      # Never overwrite a rate an admin has already tuned.
      category.rate_value = rate_value if category.new_record?
      category.save!
    end
  end

  def self.default
    find_by(key: "member")
  end

  def per_km?      = rate_mode == "per_km"
  def multiplier?  = rate_mode == "multiplier"
  def double_rate? = multiplier? && rate_value.to_f == 2.0

  # What this category charges, given the normally-calculated amount and the
  # distance driven. The two modes are deliberately exclusive: the state rate
  # replaces the normal calculation rather than scaling it.
  def charge_for(normal_amount:, km:)
    if per_km?
      (km.to_i * rate_value).round(2)
    else
      (normal_amount.to_d * rate_value).round(2)
    end
  end
end
