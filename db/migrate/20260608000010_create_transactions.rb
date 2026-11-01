class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :booking, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :description, null: false
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
