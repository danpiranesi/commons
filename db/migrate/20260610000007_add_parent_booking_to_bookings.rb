class AddParentBookingToBookings < ActiveRecord::Migration[8.1]
  def change
    add_reference :bookings, :parent_booking, foreign_key: { to_table: :bookings }, null: true
  end
end
