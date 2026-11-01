class CreateResourcePrices < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_prices do |t|
      t.references :resource, null: false, foreign_key: true
      t.string :user_type, null: false
      t.decimal :day_rate, precision: 10, scale: 2, null: false, default: 0
      t.decimal :km_rate, precision: 10, scale: 4, null: false, default: 0
      t.decimal :base_fee, precision: 10, scale: 2, null: false, default: 0

      t.timestamps
    end

    add_index :resource_prices, [:resource_id, :user_type], unique: true
  end
end
