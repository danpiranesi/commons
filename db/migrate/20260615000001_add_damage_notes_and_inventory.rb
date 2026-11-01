class AddDamageNotesAndInventory < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :damage_notes, :text
    add_column :resources, :inventory_count, :integer, null: false, default: 1
  end
end
