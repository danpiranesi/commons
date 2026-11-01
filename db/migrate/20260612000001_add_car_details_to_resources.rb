class AddCarDetailsToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :color, :string
    add_column :resources, :make, :string
    add_column :resources, :location, :string
  end
end
