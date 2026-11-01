class CreateResourceStats < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_stats do |t|
      t.references :resource, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :data, default: {}

      t.timestamps
    end
  end
end
