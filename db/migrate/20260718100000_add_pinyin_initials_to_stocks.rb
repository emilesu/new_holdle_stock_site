class AddPinyinInitialsToStocks < ActiveRecord::Migration[7.1]
  def change
    add_column :stocks, :pinyin_initials, :string, comment: "中文名拼音首字母（如'平安银行'→'PAYH'），用于搜索"
    add_index :stocks, :pinyin_initials, name: "idx_stocks_pinyin_initials"
  end
end
