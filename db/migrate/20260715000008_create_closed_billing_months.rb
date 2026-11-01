class CreateClosedBillingMonths < ActiveRecord::Migration[8.1]
  def change
    create_table :closed_billing_months do |t|
      t.string :billing_month, null: false
      t.timestamps
    end
    add_index :closed_billing_months, :billing_month, unique: true
  end
end
