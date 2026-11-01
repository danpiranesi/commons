class AddRegularUserToResources < ActiveRecord::Migration[8.1]
  # The car's regular user as a member record. The free-text regular_driver
  # column is a display fallback for non-members.
  def change
    add_reference :resources, :regular_user, null: true, foreign_key: { to_table: :users }
  end
end
