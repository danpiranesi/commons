class CreateResourceCompatibilities < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_compatibilities do |t|
      t.references :resource, null: false, foreign_key: true
      t.references :accessory, null: false, foreign_key: { to_table: :resources }

      t.timestamps
    end

    add_index :resource_compatibilities, [:resource_id, :accessory_id], unique: true
  end
end
