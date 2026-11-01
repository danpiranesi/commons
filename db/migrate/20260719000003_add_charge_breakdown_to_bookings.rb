class AddChargeBreakdownToBookings < ActiveRecord::Migration[8.1]
  def change
    # Itemized charge frozen at completion, so a receipt matches what was billed
    # even if rates change later.
    add_column :bookings, :charge_breakdown, :jsonb
  end
end
