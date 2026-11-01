class AddBillingMonthToBookings < ActiveRecord::Migration[8.1]
  def change
    # YYYYMM string, derived from completed_at; admins can override it for late
    # submissions.
    add_column :bookings, :billing_month, :string
    add_index  :bookings, :billing_month
  end
end
