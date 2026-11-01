class AddUsernameToUsers < ActiveRecord::Migration[8.1]
  # Administration username (distinct from discourse_username, which
  # comes from the forum SSO).
  def change
    add_column :users, :username, :string
  end
end
