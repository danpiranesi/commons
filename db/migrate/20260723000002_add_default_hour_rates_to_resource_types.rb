class AddDefaultHourRatesToResourceTypes < ActiveRecord::Migration[8.1]
  def change
    # Per-user-type hourly rate inherited by resources that set no price of their
    # own. { "resident" => "5.0", ... }
    add_column :resource_types, :default_hour_rates, :jsonb, default: {}, null: false
  end
end
