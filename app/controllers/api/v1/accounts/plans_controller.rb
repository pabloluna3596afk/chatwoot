class Api::V1::Accounts::PlansController < Api::V1::Accounts::BaseController
  def index
    @plans = Plan.catalog
  end
end
