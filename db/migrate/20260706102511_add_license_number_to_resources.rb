class AddLicenseNumberToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :license_number, :string
  end
end
