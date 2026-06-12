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

ActiveRecord::Schema[7.1].define(version: 2026_06_12_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "chapters", force: :cascade do |t|
    t.string "title"
    t.text "summary"
    t.integer "sort_num", default: 0
    t.boolean "is_published", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "financial_reports", force: :cascade do |t|
    t.bigint "stock_id", null: false
    t.date "report_date"
    t.string "report_type"
    t.string "currency"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "market", default: "US", null: false, comment: "市场类型（US/A股等）"
    t.string "status", default: "pending", comment: "爬取状态（pending/success/failed）"
    t.integer "retry_count", default: 0, comment: "重试次数"
    t.datetime "last_crawled_at", comment: "最后爬取时间"
    t.index ["market"], name: "index_financial_reports_on_market"
    t.index ["stock_id", "report_date", "report_type"], name: "idx_on_stock_id_report_date_report_type_c30446abbc", unique: true
    t.index ["stock_id"], name: "index_financial_reports_on_stock_id"
  end

  create_table "income_statements", force: :cascade do |t|
    t.bigint "financial_report_id", null: false, comment: "关联财务报告主表ID"
    t.bigint "stock_id", null: false, comment: "股票ID，关联stocks表"
    t.date "report_date", null: false, comment: "财报日期"
    t.string "market", default: "US", null: false, comment: "市场类型（US/A股等）"
    t.string "report_type", comment: "报告类型（年度/季度）"
    t.string "currency", comment: "货币类型"
    t.decimal "total_revenue", precision: 15, scale: 2, comment: "总营收"
    t.decimal "operating_revenue", precision: 15, scale: 2, comment: "营业收入"
    t.decimal "operating_cost", precision: 15, scale: 2, comment: "营业成本"
    t.decimal "gross_profit", precision: 15, scale: 2, comment: "毛利润"
    t.decimal "gross_margin", precision: 15, scale: 4, comment: "毛利率"
    t.decimal "operating_expense", precision: 15, scale: 2, comment: "营业费用"
    t.decimal "selling_expense", precision: 15, scale: 2, comment: "销售费用"
    t.decimal "admin_expense", precision: 15, scale: 2, comment: "管理费用"
    t.decimal "rd_expense", precision: 15, scale: 2, comment: "研发费用"
    t.decimal "operating_income", precision: 15, scale: 2, comment: "营业利润"
    t.decimal "non_operating_income", precision: 15, scale: 2, comment: "非营业收益"
    t.decimal "non_operating_expense", precision: 15, scale: 2, comment: "非营业支出"
    t.decimal "ebit", precision: 15, scale: 2, comment: "息税前利润"
    t.decimal "interest_expense", precision: 15, scale: 2, comment: "利息费用"
    t.decimal "income_before_tax", precision: 15, scale: 2, comment: "税前利润"
    t.decimal "income_tax", precision: 15, scale: 2, comment: "所得税费用"
    t.decimal "net_income", precision: 15, scale: 2, comment: "净利润"
    t.decimal "net_income_to_shareholders", precision: 15, scale: 2, comment: "归属于母公司股东净利润"
    t.decimal "basic_eps", precision: 15, scale: 4, comment: "基本每股收益"
    t.decimal "diluted_eps", precision: 15, scale: 4, comment: "稀释每股收益"
    t.decimal "weighted_avg_shares", precision: 15, scale: 2, comment: "加权平均股数"
    t.decimal "diluted_avg_shares", precision: 15, scale: 2, comment: "稀释加权平均股数"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["financial_report_id"], name: "index_income_statements_on_financial_report_id"
    t.index ["stock_id", "report_date", "market"], name: "index_income_statements_on_stock_id_and_report_date_and_market", unique: true
    t.index ["stock_id"], name: "index_income_statements_on_stock_id"
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

  add_foreign_key "financial_reports", "stocks"
  add_foreign_key "income_statements", "financial_reports"
  add_foreign_key "income_statements", "stocks"
  add_foreign_key "lessons", "chapters"
end
