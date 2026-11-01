class AddBookingHorizonToSiteSettings < ActiveRecord::Migration[8.1]
  # How many days ahead a member may book. 0 means no limit.
  def change
    add_column :site_settings, :booking_horizon_days, :integer, null: false, default: 45
  end
end
