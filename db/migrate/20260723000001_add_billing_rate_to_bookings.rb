class AddBillingRateToBookings < ActiveRecord::Migration[8.1]
  def change
    # What rate was applied to this trip's charge, frozen at completion so a later
    # change to a category's rate never rewrites an already-issued receipt.
    #   { mode:, value:, category:, base:, charged: }
    add_column :bookings, :billing_rate, :jsonb
  end
end
