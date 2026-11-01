class AddAccountingFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Account number in the bookkeeping software, used by the accounting export.
    add_column :users, :accounting_account, :string
    # Name used in the accounting export; may differ from users.name.
    add_column :users, :accounting_name, :string
    # Short initials (e.g. "AB"), used in search results and the calendar.
    add_column :users, :initials, :string
    # Housing unit identifier, for admin search.
    add_column :users, :housing_unit, :string

    # Pre-seeded users get their discourse_id on first SSO login (matched by email).
    change_column_null :users, :discourse_id, true
  end
end
