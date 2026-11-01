class AddRideshareAndDestinationToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :destination, :string
    add_column :bookings, :rideshare_available, :boolean, null: false, default: true
  end
end
