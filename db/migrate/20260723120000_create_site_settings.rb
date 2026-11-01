class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings do |t|
      t.text :homepage_header_da
      t.text :homepage_header_en

      t.timestamps
    end
  end
end
