class Api::V1::Accounts::Captain::UsageBreakdownController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :validate_bucket

  def show
    period = @current_account.current_usage_period
    render json: Captain::UsageBreakdownBuilder.new(account: @current_account, period: period, bucket: params[:bucket]).build
  end

  private

  def validate_bucket
    return if params[:bucket].blank? || Captain::UsageBreakdownBuilder::BUCKETS.include?(params[:bucket])

    render json: { error: 'Invalid bucket' }, status: :unprocessable_entity
  end

  def check_admin_authorization?
    return if Current.account_user&.administrator?

    render json: { error: I18n.t('errors.access_denied') }, status: :forbidden
  end
end
