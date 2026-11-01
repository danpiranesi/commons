# Links a person to a group they are allowed to book on behalf of.
class BillingGroupMembership < ApplicationRecord
  belongs_to :user
  belongs_to :billing_group

  validates :user_id, uniqueness: { scope: :billing_group_id }
end
