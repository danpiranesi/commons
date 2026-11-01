class AddBookingRulesToResourceTypes < ActiveRecord::Migration[8.1]
  def change
    # Per-type lifecycle rules (buffers, required odometer, extension, etc.).
    # Empty {} means BookingRules::DEFAULTS.
    add_column :resource_types, :booking_rules, :jsonb, default: {}, null: false
  end
end
