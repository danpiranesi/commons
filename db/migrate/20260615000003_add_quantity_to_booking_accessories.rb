class AddQuantityToBookingAccessories < ActiveRecord::Migration[8.1]
  def change
    add_column :booking_accessories, :quantity, :integer, null: false, default: 1
  end
end
