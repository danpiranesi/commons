class AddHomeCarMaxHoursToSiteSettings < ActiveRecord::Migration[8.1]
  # How long a home car may be booked for in one go. 0 means no limit.
  def change
    add_column :site_settings, :home_car_max_hours, :integer, default: 3, null: false
  end
end
