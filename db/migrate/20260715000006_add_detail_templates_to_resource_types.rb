class AddDetailTemplatesToResourceTypes < ActiveRecord::Migration[8.1]
  def change
    # Controls which fields appear on the public resource detail page (resources#show).
    add_column :resource_types, :detail_template, :jsonb, default: {}, null: false
    # Controls which fields appear on the booking detail page (bookings#show).
    add_column :resource_types, :booking_template, :jsonb, default: {}, null: false
  end
end
