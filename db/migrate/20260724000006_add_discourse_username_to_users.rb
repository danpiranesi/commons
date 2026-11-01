class AddDiscourseUsernameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :discourse_username, :string
  end
end
