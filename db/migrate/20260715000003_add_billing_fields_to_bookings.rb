class AddBillingFieldsToBookings < ActiveRecord::Migration[8.1]
  def change
    # Denormalized price written by ReservationCompletionService. The ledger
    # Transaction remains the financial record of truth.
    add_column :bookings, :total_amount, :decimal, precision: 10, scale: 2
    add_column :bookings, :completed_at, :datetime
  end
end
