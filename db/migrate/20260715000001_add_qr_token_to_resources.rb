class AddQrTokenToResources < ActiveRecord::Migration[8.1]
  def up
    add_column :resources, :qr_token, :string
    add_index  :resources, :qr_token, unique: true

    # Backfill so every existing resource is scannable.
    Resource.reset_column_information
    Resource.where(qr_token: nil).find_each do |resource|
      resource.update_column(:qr_token, Resource.generate_unique_qr_token)
    end
  end

  def down
    remove_index  :resources, :qr_token
    remove_column :resources, :qr_token
  end
end
