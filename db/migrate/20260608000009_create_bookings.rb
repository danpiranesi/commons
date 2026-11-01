class CreateBookings < ActiveRecord::Migration[8.1]
  def change
    create_table :bookings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :resource, null: false, foreign_key: true
      t.references :booking_period, foreign_key: true
      t.datetime :start_at, null: false
      t.datetime :end_at, null: false
      t.string :actual_driver
      t.integer :start_mileage
      t.integer :end_mileage
      t.string :status, null: false, default: "active"
      t.text :notes
      t.text :return_notes
      t.string :cancellation_reason

      t.timestamps
    end

    add_index :bookings, :status
    add_index :bookings, [:resource_id, :start_at, :end_at], name: "index_bookings_on_resource_and_time"
  end
end
