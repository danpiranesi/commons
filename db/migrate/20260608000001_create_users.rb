class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.integer :discourse_id, null: false
      t.string :name, null: false
      t.string :email, null: false
      t.string :user_type, null: false, default: "resident"
      t.boolean :admin, null: false, default: false

      t.timestamps
    end

    add_index :users, :discourse_id, unique: true
    add_index :users, :email, unique: true
  end
end
