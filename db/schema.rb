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

ActiveRecord::Schema[7.1].define(version: 2026_06_11_032326) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "balance_sheets", force: :cascade do |t|
    t.bigint "financial_report_id", null: false
    t.decimal "total_assets"
    t.decimal "current_assets"
    t.decimal "non_current_assets"
    t.decimal "total_liabilities"
    t.decimal "current_liabilities"
    t.decimal "non_current_liabilities"
    t.decimal "total_equity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["financial_report_id"], name: "index_balance_sheets_on_financial_report_id"
  end

  create_table "cash_flows", force: :cascade do |t|
    t.bigint "financial_report_id", null: false
    t.decimal "operating_cash_flow"
    t.decimal "investing_cash_flow"
    t.decimal "financing_cash_flow"
    t.decimal "net_cash_flow"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["financial_report_id"], name: "index_cash_flows_on_financial_report_id"
  end

  create_table "chapters", force: :cascade do |t|
    t.string "title"
    t.text "summary"
    t.integer "sort_num", default: 0
    t.boolean "is_published", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "financial_indicators", force: :cascade do |t|
    t.bigint "financial_report_id", null: false
    t.decimal "roe"
    t.decimal "roa"
    t.decimal "gross_margin"
    t.decimal "net_margin"
    t.decimal "debt_to_equity"
    t.decimal "current_ratio"
    t.decimal "quick_ratio"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["financial_report_id"], name: "index_financial_indicators_on_financial_report_id"
  end

  create_table "financial_reports", force: :cascade do |t|
    t.bigint "stock_id", null: false
    t.date "report_date"
    t.string "report_type"
    t.string "currency"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stock_id", "report_date", "report_type"], name: "idx_on_stock_id_report_date_report_type_c30446abbc", unique: true
    t.index ["stock_id"], name: "index_financial_reports_on_stock_id"
  end

  create_table "income_statements", force: :cascade do |t|
    t.bigint "financial_report_id", null: false
    t.decimal "revenue"
    t.decimal "cost_of_revenue"
    t.decimal "gross_profit"
    t.decimal "operating_expenses"
    t.decimal "operating_income"
    t.decimal "net_income"
    t.decimal "eps"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["financial_report_id"], name: "index_income_statements_on_financial_report_id"
  end

  create_table "lessons", force: :cascade do |t|
    t.bigint "chapter_id", null: false
    t.string "title"
    t.text "content"
    t.integer "sort_num", default: 0
    t.boolean "is_published", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chapter_id"], name: "index_lessons_on_chapter_id"
  end

  create_table "stocks", force: :cascade do |t|
    t.string "symbol"
    t.string "name"
    t.string "market"
    t.string "industry"
    t.string "exchange"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["symbol", "market"], name: "index_stocks_on_symbol_and_market", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.string "nickname"
    t.integer "member_level", default: 0
    t.datetime "member_expire_at"
    t.string "role", default: "user"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "balance_sheets", "financial_reports"
  add_foreign_key "cash_flows", "financial_reports"
  add_foreign_key "financial_indicators", "financial_reports"
  add_foreign_key "financial_reports", "stocks"
  add_foreign_key "income_statements", "financial_reports"
  add_foreign_key "lessons", "chapters"
end
