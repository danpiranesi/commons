class AddBilledUntilToBookings < ActiveRecord::Migration[8.1]
  # Billing floor set when an in-progress booking is shortened: the driver stays
  # liable up to this time. See Booking#billed_hours.
  def change
    add_column :bookings, :billed_until, :datetime
  end
end
