class Account < ApplicationRecord
  belongs_to :user
  has_many :transactions, dependent: :restrict_with_error

  def balance
    transactions.sum(:amount)
  end
end
