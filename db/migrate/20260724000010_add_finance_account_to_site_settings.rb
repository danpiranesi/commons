class AddFinanceAccountToSiteSettings < ActiveRecord::Migration[8.1]
  # The balancing account on the bank-transfer export.
  def change
    add_column :site_settings, :finance_account, :string, default: "2400", null: false
  end
end
