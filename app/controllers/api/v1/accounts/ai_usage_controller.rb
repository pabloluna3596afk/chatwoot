class Api::V1::Accounts::AiUsageController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    now = Time.current
    period = @current_account.account_plan_usages.open
                             .where('period_start <= ? AND period_end > ?', now, now).first
    return render json: { period_start: nil, period_end: nil, daily: [] } unless period

    usage_messages = AiUsageEvent
                     .where(account_id: @current_account.id, created_at: period.period_start...period.period_end)
                     .select(:usage_group_id, :bucket, 'MIN(created_at) AS created_at')
                     .group(:usage_group_id, :bucket)
    daily = AiUsageEvent.from(usage_messages, :usage_messages)
                        .select('DATE(usage_messages.created_at) AS day, usage_messages.bucket, COUNT(*) AS messages')
                        .group('DATE(usage_messages.created_at)', 'usage_messages.bucket')
                        .order('DATE(usage_messages.created_at)')
                        .map { |row| { day: row.day, bucket: row.bucket, messages: row.messages.to_i } }

    render json: { period_start: period.period_start, period_end: period.period_end, daily: daily }
  end

  private

  def check_admin_authorization?
    return if Current.account_user&.administrator?

    render json: { error: I18n.t('errors.access_denied') }, status: :forbidden
  end
end
