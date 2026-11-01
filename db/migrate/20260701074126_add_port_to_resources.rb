class AddPortToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :port, :string
  end
end
