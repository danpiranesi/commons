# Something a booking can be made on behalf of: a work group, an interest group,
# a service group, or a Bæredygtig Befordring account. Groups are their own
# records rather than user accounts, so an admin can add one without a login.
class BillingGroup < ApplicationRecord
  belongs_to :billing_category
  has_many :bookings, dependent: :nullify
  has_many :billing_group_memberships, dependent: :destroy
  has_many :members, through: :billing_group_memberships, source: :user

  validates :name, presence: true
  validates :code, uniqueness: true, allow_blank: true

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  # Groups are charged at their category's rate, never at the rate of whoever
  # happened to drive.
  delegate :charge_for, :section, :per_km?, to: :billing_category

  def display_name
    code.present? ? "#{name} (#{code})" : name
  end
end
