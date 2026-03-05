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

ActiveRecord::Schema[7.2].define(version: 2024_03_01_000006) do
  create_table "accounts", charset: "latin1", force: :cascade do |t|
    t.string "name", null: false
    t.string "industry"
    t.string "phone"
    t.string "email"
    t.text "address"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "activities", charset: "latin1", force: :cascade do |t|
    t.string "activityable_type", null: false
    t.bigint "activityable_id", null: false
    t.integer "activity_type", null: false
    t.string "subject", null: false
    t.text "description"
    t.datetime "due_at"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "contacts", charset: "latin1", force: :cascade do |t|
    t.bigint "account_id"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "title"
    t.string "email", null: false
    t.string "phone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_contacts_on_account_id"
  end

  create_table "deals", charset: "latin1", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "contact_id"
    t.string "name", null: false
    t.decimal "value", precision: 12, scale: 2, default: "0.0"
    t.integer "stage", default: 0
    t.date "expected_close_date"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_deals_on_account_id"
    t.index ["contact_id"], name: "index_deals_on_contact_id"
  end

  create_table "leads", charset: "latin1", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "email", null: false
    t.string "company"
    t.string "phone"
    t.integer "status", default: 0
    t.integer "source", default: 0
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", charset: "latin1", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "contacts", "accounts"
  add_foreign_key "deals", "accounts"
  add_foreign_key "deals", "contacts"
end
