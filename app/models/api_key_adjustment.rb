# T7 Phase2：key 次数调整记录（后台补偿/退款，含管理员与备注）
class ApiKeyAdjustment < ApplicationRecord
  belongs_to :api_key
  belongs_to :user
  belongs_to :admin, class_name: "User"

  validates :delta, presence: true, numericality: { only_integer: true, other_than: 0 }
  validates :reason, presence: true
end
