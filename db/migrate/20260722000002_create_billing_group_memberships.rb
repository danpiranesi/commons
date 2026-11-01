# Who may book on behalf of a group; only members can charge a trip to it.
class CreateBillingGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_group_memberships do |t|
      t.references :user,           null: false, foreign_key: true
      t.references :billing_group,  null: false, foreign_key: true
      t.timestamps
    end
    add_index :billing_group_memberships, [:user_id, :billing_group_id],
              unique: true, name: "index_group_memberships_on_user_and_group"
  end
end
