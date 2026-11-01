# A billing category carries a rate rule (multiplier or per-km). It applies to a
# person (users.billing_category_id) or to a group a booking is made on behalf
# of (billing_groups.billing_category_id); a group booking uses the group's rate.
class CreateBillingCategoriesAndGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_categories do |t|
      t.string  :key,        null: false            # e.g. member, guest, working_group
      t.string  :name_da,    null: false            # label printed on the accounting sheet
      t.integer :section,    null: false, default: 1 # which block of the sheet it prints in
      t.string  :rate_mode,  null: false, default: "multiplier" # multiplier | per_km
      t.decimal :rate_value, null: false, default: "1.0", precision: 10, scale: 4
      t.string  :collection, null: false, default: "bank"       # bank | invoice | internal
      t.boolean :personal,   null: false, default: false        # can a person be this?
      t.integer :position,   null: false, default: 0
      t.timestamps
    end
    add_index :billing_categories, :key, unique: true

    # Groups a booking can be made on behalf of (working groups, projects, ...).
    create_table :billing_groups do |t|
      t.string     :name, null: false
      t.string     :code                                # short code printed on the accounting sheet
      t.references :billing_category, null: false, foreign_key: true
      t.boolean    :active, null: false, default: true
      t.timestamps
    end
    add_index :billing_groups, :code, unique: true

    # Nullable: a person's own category, assigned by an admin.
    add_reference :users, :billing_category, foreign_key: true

    # Nullable: set only when the trip was made on behalf of a group.
    add_reference :bookings, :billing_group, foreign_key: true
  end
end
