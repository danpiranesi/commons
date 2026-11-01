class ChangePricingToHourly < ActiveRecord::Migration[8.1]
  def change
    add_column :resource_prices, :hour_rate, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :resource_prices, :min_charge, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :resource_prices, :day_cap_hours, :integer, default: 16, null: false
    remove_column :resource_prices, :base_fee, :decimal, precision: 10, scale: 2, default: 0, null: false
  end
end
