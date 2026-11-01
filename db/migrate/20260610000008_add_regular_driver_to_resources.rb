class AddRegularDriverToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :regular_driver, :string
  end
end
