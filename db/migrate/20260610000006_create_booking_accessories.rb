class CreateBookingAccessories < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_accessories do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :accessory, null: false, foreign_key: { to_table: :resources }

      t.timestamps
    end

    add_index :booking_accessories, [:booking_id, :accessory_id], unique: true
  end
end
