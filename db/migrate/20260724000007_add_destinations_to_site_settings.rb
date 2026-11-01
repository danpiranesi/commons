class AddDestinationsToSiteSettings < ActiveRecord::Migration[8.1]
  # A JSON array of { "group" => ..., "cities" => [...] } to preserve group order.
  # nil falls back to DEFAULT_DESTINATIONS.
  def change
    add_column :site_settings, :destinations, :jsonb
  end
end
