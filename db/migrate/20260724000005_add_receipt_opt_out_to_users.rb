class AddReceiptOptOutToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :receipt_opt_out, :boolean, default: false, null: false
  end
end
