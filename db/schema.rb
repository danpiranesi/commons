# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_05_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_accounts_on_user_id", unique: true
  end

  create_table "billing_categories", force: :cascade do |t|
    t.string "collection", default: "bank", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name_da", null: false
    t.boolean "personal", default: false, null: false
    t.integer "position", default: 0, null: false
    t.string "rate_mode", default: "multiplier", null: false
    t.decimal "rate_value", precision: 10, scale: 4, default: "1.0", null: false
    t.integer "section", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_billing_categories_on_key", unique: true
  end

  create_table "billing_group_memberships", force: :cascade do |t|
    t.bigint "billing_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["billing_group_id"], name: "index_billing_group_memberships_on_billing_group_id"
    t.index ["user_id", "billing_group_id"], name: "index_group_memberships_on_user_and_group", unique: true
    t.index ["user_id"], name: "index_billing_group_memberships_on_user_id"
  end

  create_table "billing_groups", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "billing_category_id", null: false
    t.string "code"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_category_id"], name: "index_billing_groups_on_billing_category_id"
    t.index ["code"], name: "index_billing_groups_on_code", unique: true
  end

  create_table "booking_accessories", force: :cascade do |t|
    t.bigint "accessory_id", null: false
    t.bigint "booking_id", null: false
    t.datetime "created_at", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["accessory_id"], name: "index_booking_accessories_on_accessory_id"
    t.index ["booking_id", "accessory_id"], name: "index_booking_accessories_on_booking_id_and_accessory_id", unique: true
    t.index ["booking_id"], name: "index_booking_accessories_on_booking_id"
  end

  create_table "booking_periods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "end_date", null: false
    t.string "name", null: false
    t.datetime "opens_at"
    t.date "start_date", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
  end

  create_table "bookings", force: :cascade do |t|
    t.string "actual_driver"
    t.datetime "billed_until"
    t.bigint "billing_group_id"
    t.string "billing_month"
    t.jsonb "billing_rate"
    t.bigint "booking_period_id"
    t.integer "bridge_storebælt_qty", default: 0, null: false
    t.integer "bridge_øresund_qty", default: 0, null: false
    t.string "cancellation_reason"
    t.jsonb "charge_breakdown"
    t.datetime "checked_in_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "destination"
    t.datetime "end_at", null: false
    t.integer "end_mileage"
    t.boolean "may_return_early", default: false, null: false
    t.text "notes"
    t.bigint "parent_booking_id"
    t.string "payer"
    t.bigint "resource_id", null: false
    t.text "return_notes"
    t.boolean "rideshare_available", default: true, null: false
    t.datetime "start_at", null: false
    t.integer "start_mileage"
    t.string "status", default: "active", null: false
    t.decimal "total_amount", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["billing_group_id"], name: "index_bookings_on_billing_group_id"
    t.index ["billing_month"], name: "index_bookings_on_billing_month"
    t.index ["booking_period_id"], name: "index_bookings_on_booking_period_id"
    t.index ["parent_booking_id"], name: "index_bookings_on_parent_booking_id"
    t.index ["resource_id", "start_at", "end_at"], name: "index_bookings_on_resource_and_time"
    t.index ["resource_id"], name: "index_bookings_on_resource_id"
    t.index ["status"], name: "index_bookings_on_status"
    t.index ["user_id"], name: "index_bookings_on_user_id"
  end

  create_table "closed_billing_months", force: :cascade do |t|
    t.string "billing_month", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_month"], name: "index_closed_billing_months_on_billing_month", unique: true
  end

  create_table "pricing_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.integer "max_days"
    t.integer "min_days"
    t.decimal "multiplier", precision: 5, scale: 3, null: false
    t.bigint "resource_id", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_id"], name: "index_pricing_rules_on_resource_id"
  end

  create_table "resource_compatibilities", force: :cascade do |t|
    t.bigint "accessory_id", null: false
    t.datetime "created_at", null: false
    t.bigint "resource_id", null: false
    t.datetime "updated_at", null: false
    t.index ["accessory_id"], name: "index_resource_compatibilities_on_accessory_id"
    t.index ["resource_id", "accessory_id"], name: "index_resource_compatibilities_on_resource_id_and_accessory_id", unique: true
    t.index ["resource_id"], name: "index_resource_compatibilities_on_resource_id"
  end

  create_table "resource_prices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "day_cap_hours", default: 16, null: false
    t.decimal "day_rate", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "hour_rate", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "km_rate", precision: 10, scale: 4, default: "0.0", null: false
    t.decimal "min_charge", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "resource_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_type", null: false
    t.index ["resource_id", "user_type"], name: "index_resource_prices_on_resource_id_and_user_type", unique: true
    t.index ["resource_id"], name: "index_resource_prices_on_resource_id"
  end

  create_table "resource_stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}
    t.bigint "resource_id", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_id"], name: "index_resource_stats_on_resource_id", unique: true
  end

  create_table "resource_types", force: :cascade do |t|
    t.string "billing_type", default: "per_day_and_km", null: false
    t.jsonb "booking_rules", default: {}, null: false
    t.jsonb "booking_template", default: {}, null: false
    t.jsonb "card_template", default: {}, null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.jsonb "default_hour_rates", default: {}, null: false
    t.jsonb "detail_template", default: {}, null: false
    t.string "icon"
    t.boolean "inherit_rules_from_car", default: false, null: false
    t.string "name", null: false
    t.integer "sort_order", default: 0, null: false
    t.jsonb "stats_schema", default: {}
    t.datetime "updated_at", null: false
  end

  create_table "resources", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.text "damage_notes"
    t.text "description"
    t.boolean "electric", default: false, null: false
    t.boolean "home_car", default: false, null: false
    t.integer "inventory_count", default: 1, null: false
    t.string "license_number"
    t.string "location"
    t.string "make"
    t.string "name", null: false
    t.string "port"
    t.string "qr_token"
    t.datetime "recharge_until"
    t.string "regular_driver"
    t.bigint "regular_user_id"
    t.bigint "resource_type_id", null: false
    t.string "status", default: "active", null: false
    t.string "unavailable_reason"
    t.date "unavailable_until"
    t.datetime "updated_at", null: false
    t.index ["qr_token"], name: "index_resources_on_qr_token", unique: true
    t.index ["regular_user_id"], name: "index_resources_on_regular_user_id"
    t.index ["resource_type_id"], name: "index_resources_on_resource_type_id"
    t.index ["status"], name: "index_resources_on_status"
  end

  create_table "site_settings", force: :cascade do |t|
    t.integer "booking_horizon_days", default: 45, null: false
    t.decimal "car_minimum_price", precision: 10, scale: 2, default: "20.0", null: false
    t.datetime "created_at", null: false
    t.jsonb "destinations"
    t.boolean "destinations_enabled", default: false, null: false
    t.string "finance_account", default: "2400", null: false
    t.integer "home_car_max_hours", default: 3, null: false
    t.decimal "home_car_minimum_price", precision: 10, scale: 2, default: "10.0", null: false
    t.text "homepage_header_da"
    t.text "homepage_header_en"
    t.datetime "updated_at", null: false
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.bigint "booking_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "description", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["booking_id"], name: "index_transactions_on_booking_id"
    t.index ["created_by_id"], name: "index_transactions_on_created_by_id"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "accounting_account"
    t.string "accounting_name"
    t.boolean "admin", default: false, null: false
    t.bigint "billing_category_id"
    t.boolean "business_override", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "discourse_id"
    t.string "discourse_username"
    t.string "email", null: false
    t.string "housing_unit"
    t.string "initials"
    t.string "locale", default: "da", null: false
    t.string "name", null: false
    t.boolean "name_set_by_admin", default: false, null: false
    t.string "phone"
    t.boolean "receipt_opt_out", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "user_type", default: "resident", null: false
    t.string "username"
    t.jsonb "working_hours"
    t.index ["billing_category_id"], name: "index_users_on_billing_category_id"
    t.index ["discourse_id"], name: "index_users_on_discourse_id", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "accounts", "users"
  add_foreign_key "billing_group_memberships", "billing_groups"
  add_foreign_key "billing_group_memberships", "users"
  add_foreign_key "billing_groups", "billing_categories"
  add_foreign_key "booking_accessories", "bookings"
  add_foreign_key "booking_accessories", "resources", column: "accessory_id"
  add_foreign_key "bookings", "billing_groups"
  add_foreign_key "bookings", "booking_periods"
  add_foreign_key "bookings", "bookings", column: "parent_booking_id"
  add_foreign_key "bookings", "resources"
  add_foreign_key "bookings", "users"
  add_foreign_key "pricing_rules", "resources"
  add_foreign_key "resource_compatibilities", "resources"
  add_foreign_key "resource_compatibilities", "resources", column: "accessory_id"
  add_foreign_key "resource_prices", "resources"
  add_foreign_key "resource_stats", "resources"
  add_foreign_key "resources", "resource_types"
  add_foreign_key "resources", "users", column: "regular_user_id"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "bookings"
  add_foreign_key "transactions", "users"
  add_foreign_key "transactions", "users", column: "created_by_id"
  add_foreign_key "users", "billing_categories"
end
