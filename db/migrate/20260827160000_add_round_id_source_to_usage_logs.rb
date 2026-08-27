class AddRoundIdSourceToUsageLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :usage_logs, :round_id_source, :string,
               comment: "round_id 来源：caller=调用方传入 / generated=Rails 兜底生成（调用方未传）/ NULL=老数据"
  end
end
