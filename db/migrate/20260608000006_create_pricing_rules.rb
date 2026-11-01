class CreatePricingRules < ActiveRecord::Migration[8.1]
  def change
    create_table :pricing_rules do |t|
      t.references :resource, null: false, foreign_key: true
      t.integer :min_days
      t.integer :max_days
      t.decimal :multiplier, precision: 5, scale: 3, null: false
      t.string :description

      t.timestamps
    end
  end
end
