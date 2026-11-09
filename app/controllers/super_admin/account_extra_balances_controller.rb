class SuperAdmin::AccountExtraBalancesController < SuperAdmin::ApplicationController
  def new
    resource = AccountExtraBalance.new(account_id: params[:account_id])
    render locals: { page: Administrate::Page::Form.new(dashboard, resource) }
  end

  def create
    attributes = resource_params
    units = attributes[:units_total]
    return head :unprocessable_entity unless units.is_a?(String) && units.match?(/\A[1-9]\d*\z/)
    return head :unprocessable_entity unless ExtraPack::BUCKETS.include?(attributes[:bucket])

    balance = Account.find(attributes[:account_id]).grant_extra_balance!(
      bucket: attributes[:bucket], units: units.to_i, source: 'courtesy',
      expires_at: AccountExtraBalance::VALIDITY.from_now
    )
    redirect_to [namespace, balance]
  end
end
