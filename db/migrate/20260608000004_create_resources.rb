class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_table :resources do |t|
      t.string :name, null: false
      t.text :description
      t.references :resource_type, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.string :unavailable_reason
      t.date :unavailable_until

      t.timestamps
    end

    add_index :resources, :status
  end
end
