class AddCarMinimumPriceToSiteSettings < ActiveRecord::Migration[8.1]
  # Minimum price of a car reservation (time + km). Home cars use the lower home
  # minimum; other resources use their own min_charge.
  def change
    add_column :site_settings, :car_minimum_price, :decimal, precision: 10, scale: 2, null: false, default: "20.0"
    add_column :site_settings, :home_car_minimum_price, :decimal, precision: 10, scale: 2, null: false, default: "10.0"
  end
end
