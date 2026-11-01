class AddDestinationsEnabledToSiteSettings < ActiveRecord::Migration[8.1]
  # Whether members pick a destination from the curated list instead of typing it.
  def change
    add_column :site_settings, :destinations_enabled, :boolean, default: false, null: false
  end
end
