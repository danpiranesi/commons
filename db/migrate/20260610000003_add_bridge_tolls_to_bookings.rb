class AddBridgeTollsToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :bridge_storebælt, :boolean, null: false, default: false
    add_column :bookings, :bridge_øresund, :boolean, null: false, default: false
  end
end
