class AddBusinessOverrideToUsers < ActiveRecord::Migration[8.1]
  # Personal business use is normally limited to members, whose charges are
  # deducted from their pay. This flag lets an admin grant it to others.
  def change
    add_column :users, :business_override, :boolean, default: false, null: false
  end
end
