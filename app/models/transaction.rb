class Transaction < ApplicationRecord
  belongs_to :user
  belongs_to :account
  belongs_to :booking, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :amount, presence: true
  validates :description, presence: true

  # Transactions are immutable — corrections via offsetting transactions only
  def readonly?
    persisted?
  end
end
