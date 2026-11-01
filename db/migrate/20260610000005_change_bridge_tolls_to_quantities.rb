class ChangeBridgeTollsToQuantities < ActiveRecord::Migration[8.1]
  def change
    remove_column :bookings, :bridge_storebælt, :boolean
    remove_column :bookings, :bridge_øresund, :boolean
    add_column :bookings, :bridge_storebælt_qty, :integer, null: false, default: 0
    add_column :bookings, :bridge_øresund_qty, :integer, null: false, default: 0
    add_column :bookings, :payer, :string
  end
end
