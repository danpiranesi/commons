class AddHomeCarToResources < ActiveRecord::Migration[8.1]
  # Home cars are billed at the lower home minimum.
  def change
    add_column :resources, :home_car, :boolean, null: false, default: false
  end
end
