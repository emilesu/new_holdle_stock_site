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

ActiveRecord::Schema[7.1].define(version: 2026_06_16_005825) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "balance_sheets", force: :cascade do |t|
    t.bigint "financial_report_id", null: false, comment: "关联财务报告主表ID"
    t.bigint "stock_id", null: false, comment: "股票ID，关联stocks表"
    t.date "report_date", null: false, comment: "财报日期"
    t.string "market", default: "US", null: false, comment: "市场类型（US/A股等）"
    t.string "report_type", comment: "报告类型（年度/季度）"
    t.string "currency", comment: "货币类型"
    t.decimal "total_assets", precision: 15, scale: 2, comment: "总资产"
    t.decimal "total_liabilities", precision: 15, scale: 2, comment: "总负债"
    t.decimal "total_equity", precision: 15, scale: 2, comment: "股东权益合计"
    t.decimal "current_assets", precision: 15, scale: 2, comment: "流动资产"
    t.decimal "current_liabilities", precision: 15, scale: 2, comment: "流动负债"
    t.decimal "cash_and_cash_equivalents", precision: 15, scale: 2, comment: "现金及现金等价物"
    t.decimal "accounts_receivable", precision: 15, scale: 2, comment: "应收账款"
    t.decimal "inventory", precision: 15, scale: 2, comment: "存货"
    t.decimal "property_plant_equipment", precision: 15, scale: 2, comment: "固定资产"
    t.decimal "long_term_debt", precision: 15, scale: 2, comment: "长期负债"
    t.decimal "short_term_debt", precision: 15, scale: 2, comment: "短期负债"
    t.decimal "retained_earnings", precision: 15, scale: 2, comment: "留存收益"
    t.decimal "intangible_assets", precision: 15, scale: 2, comment: "无形资产"
    t.decimal "goodwill", precision: 15, scale: 2, comment: "商誉"
    t.decimal "investments", precision: 15, scale: 2, comment: "投资"
    t.decimal "other_current_assets", precision: 15, scale: 2, comment: "其他流动资产"
    t.decimal "other_non_current_assets", precision: 15, scale: 2, comment: "其他非流动资产"
    t.decimal "other_current_liabilities", precision: 15, scale: 2, comment: "其他流动负债"
    t.decimal "other_non_current_liabilities", precision: 15, scale: 2, comment: "其他非流动负债"
    t.decimal "common_stock", precision: 15, scale: 2, comment: "普通股"
    t.decimal "additional_paid_in_capital", precision: 15, scale: 2, comment: "资本公积"
    t.decimal "treasury_stock", precision: 15, scale: 2, comment: "库存股"
    t.decimal "non_controlling_interest", precision: 15, scale: 2, comment: "非控制权益"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["financial_report_id", "report_date"], name: "idx_balance_sheets_report_date"
    t.index ["financial_report_id"], name: "index_balance_sheets_on_financial_report_id"
    t.index ["stock_id", "report_date", "market"], name: "index_balance_sheets_on_stock_id_and_report_date_and_market", unique: true
    t.index ["stock_id"], name: "index_balance_sheets_on_stock_id"
  end

  create_table "cash_flows", force: :cascade do |t|
    t.bigint "financial_report_id", null: false, comment: "关联财务报告主表ID"
    t.bigint "stock_id", null: false, comment: "股票ID，关联stocks表"
    t.date "report_date", null: false, comment: "财报日期"
    t.string "market", default: "US", null: false, comment: "市场类型（US/A股等）"
    t.string "report_type", comment: "报告类型（年度/季度）"
    t.decimal "operating_cash_flow", precision: 15, scale: 2, comment: "经营活动现金流量净额"
    t.decimal "investing_cash_flow", precision: 15, scale: 2, comment: "投资活动现金流量净额"
    t.decimal "financing_cash_flow", precision: 15, scale: 2, comment: "筹资活动现金流量净额"
    t.decimal "net_cash_change", precision: 15, scale: 2, comment: "现金及等价物净增加额"
    t.decimal "beginning_cash", precision: 15, scale: 2, comment: "期初现金及等价物"
    t.decimal "ending_cash", precision: 15, scale: 2, comment: "期末现金及等价物"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["financial_report_id", "report_date"], name: "idx_cash_flows_report_date"
    t.index ["financial_report_id"], name: "index_cash_flows_on_financial_report_id"
    t.index ["stock_id", "report_date", "market"], name: "index_cash_flows_on_stock_id_and_report_date_and_market", unique: true
    t.index ["stock_id"], name: "index_cash_flows_on_stock_id"
  end

  create_table "chapters", force: :cascade do |t|
    t.string "title"
    t.text "summary"
    t.integer "sort_num", default: 0
    t.boolean "is_published", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "crawler_executions", force: :cascade do |t|
    t.string "task_name", null: false
    t.string "status", default: "success", null: false
    t.string "message"
    t.decimal "duration", precision: 10, scale: 2
    t.datetime "executed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["executed_at"], name: "index_crawler_executions_on_executed_at"
  end

  create_table "financial_indicators", force: :cascade do |t|
    t.bigint "financial_report_id", null: false, comment: "关联财务报告主表ID"
    t.bigint "stock_id", null: false, comment: "股票ID，关联stocks表"
    t.date "report_date", null: false, comment: "财报日期"
    t.string "market", default: "US", null: false, comment: "市场类型（US/A股等）"
    t.string "report_type", comment: "报告类型（年度/季度）"
    t.decimal "basic_eps", precision: 15, scale: 2, comment: "基本每股收益"
    t.decimal "diluted_eps", precision: 15, scale: 2, comment: "稀释每股收益"
    t.decimal "nav_ps", precision: 15, scale: 2, comment: "每股净资产"
    t.decimal "ncf_from_oa_ps", precision: 15, scale: 2, comment: "每股经营现金流"
    t.decimal "capital_reserve", precision: 15, scale: 2, comment: "资本公积"
    t.decimal "roe_avg", precision: 15, scale: 2, comment: "平均净资产收益率"
    t.decimal "roe_ttm", precision: 15, scale: 2, comment: "TTM净资产收益率"
    t.decimal "net_interest_of_ta", precision: 15, scale: 2, comment: "总资产净利率"
    t.decimal "net_sales_rate", precision: 15, scale: 2, comment: "销售净利率"
    t.decimal "asset_liab_ratio", precision: 15, scale: 2, comment: "资产负债率"
    t.decimal "current_ratio", precision: 15, scale: 2, comment: "流动比率"
    t.decimal "quick_ratio", precision: 15, scale: 2, comment: "速动比率"
    t.decimal "gross_margin", precision: 15, scale: 2, comment: "毛利率"
    t.decimal "operating_margin", precision: 15, scale: 2, comment: "营业利润率"
    t.decimal "ebitda_margin", precision: 15, scale: 2, comment: "EBITDA利润率"
    t.decimal "pe_ratio", precision: 15, scale: 2, comment: "市盈率"
    t.decimal "pb_ratio", precision: 15, scale: 2, comment: "市净率"
    t.decimal "ps_ratio", precision: 15, scale: 2, comment: "市销率"
    t.decimal "dividend_yield", precision: 15, scale: 2, comment: "股息率"
    t.decimal "payout_ratio", precision: 15, scale: 2, comment: "派息率"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["financial_report_id", "report_date"], name: "idx_fin_indicators_report_date"
    t.index ["financial_report_id"], name: "index_financial_indicators_on_financial_report_id"
    t.index ["stock_id", "report_date", "market"], name: "idx_on_stock_id_report_date_market_cbb7ad04c1", unique: true
    t.index ["stock_id"], name: "index_financial_indicators_on_stock_id"
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
    t.index ["stock_id", "report_date"], name: "idx_financial_reports_stock_date"
    t.index ["stock_id", "status"], name: "idx_financial_reports_stock_status"
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
    t.index ["financial_report_id", "report_date"], name: "idx_income_stmts_report_date"
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
    t.string "sector", comment: "行业板块（中文）"
    t.index ["sector", "market"], name: "idx_stocks_sector_market"
    t.index ["sector"], name: "index_stocks_on_sector"
    t.index ["symbol", "market"], name: "index_stocks_on_symbol_and_market", unique: true
    t.index ["symbol"], name: "idx_stocks_symbol", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "user", null: false
    t.string "nickname"
    t.integer "member_level", default: 0, null: false
    t.datetime "member_expire_at"
    t.text "bio"
    t.datetime "last_login_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "balance_sheets", "financial_reports"
  add_foreign_key "balance_sheets", "stocks"
  add_foreign_key "cash_flows", "financial_reports"
  add_foreign_key "cash_flows", "stocks"
  add_foreign_key "financial_indicators", "financial_reports"
  add_foreign_key "financial_indicators", "stocks"
  add_foreign_key "financial_reports", "stocks"
  add_foreign_key "income_statements", "financial_reports"
  add_foreign_key "income_statements", "stocks"
  add_foreign_key "lessons", "chapters"
end
