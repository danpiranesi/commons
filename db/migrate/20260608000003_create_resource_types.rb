class CreateResourceTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_types do |t|
      t.string :name, null: false
      t.string :icon
      t.string :color
      t.integer :sort_order, null: false, default: 0
      t.string :billing_type, null: false, default: "per_day_and_km"
      t.jsonb :stats_schema, default: {}

      t.timestamps
    end
  end
end
