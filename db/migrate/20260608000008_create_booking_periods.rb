class CreateBookingPeriods < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_periods do |t|
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.datetime :opens_at
      t.string :status, null: false, default: "draft"

      t.timestamps
    end
  end
end
