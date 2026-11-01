class AddElectricAndRechargeToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :electric, :boolean, null: false, default: false
    add_column :resources, :recharge_until, :datetime
  end
end
