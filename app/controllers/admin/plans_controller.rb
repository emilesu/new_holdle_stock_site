# T7 Phase2：套餐只读列表（调价走手动改库，不做 UI）
module Admin
  class PlansController < BaseController
    def index
      @plans = Plan.order(:price_cents)
    end
  end
end
