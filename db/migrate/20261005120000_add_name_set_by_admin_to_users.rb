# A name set by an admin takes precedence over the forum alias on sign-in.
class AddNameSetByAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name_set_by_admin, :boolean, default: false, null: false
  end
end
