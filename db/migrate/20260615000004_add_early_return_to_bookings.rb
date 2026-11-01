class AddEarlyReturnToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :may_return_early, :boolean, null: false, default: false
  end
end
