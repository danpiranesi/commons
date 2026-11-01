class AddPhoneToUsers < ActiveRecord::Migration[8.1]
  def change
    # Nullable: features that use it (kiosk lookup, calling the next driver)
    # degrade gracefully when it is blank.
    add_column :users, :phone, :string
  end
end
