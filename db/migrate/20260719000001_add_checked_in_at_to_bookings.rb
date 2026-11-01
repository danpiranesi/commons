class AddCheckedInAtToBookings < ActiveRecord::Migration[8.1]
  def change
    # Set when the driver checks in at the start of a trip, distinguishing a
    # started trip from a booking that is merely inside its window.
    add_column :bookings, :checked_in_at, :datetime
  end
end
