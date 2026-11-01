class Api::V1::Accounts::AiUsageController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    period = @current_account.current_usage_period
    return render json: { period_start: nil, period_end: nil, daily: [], bag_modes: bag_modes } unless period

    render json: usage_report(period)
  end

  private

  def usage_report(period)
    { period_start: period.period_start, period_end: period.period_end, daily: daily_usage(period), bag_modes: bag_modes }
  end

  def daily_usage(period)
    usage_messages = AiUsageEvent
                     .where(account_id: @current_account.id, status: 'ok',
                            created_at: period.period_start...period.period_end)
                     .select(:usage_group_id, :bucket, 'MIN(created_at) AS created_at')
                     .group(:usage_group_id, :bucket)
    AiUsageEvent.from(usage_messages, :usage_messages)
                .select('DATE(usage_messages.created_at) AS day, usage_messages.bucket, COUNT(*) AS messages')
                .group('DATE(usage_messages.created_at)', 'usage_messages.bucket')
                .order('DATE(usage_messages.created_at)')
                .map { |row| { day: row.day, bucket: row.bucket, messages: row.messages.to_i } }
  end

  def check_admin_authorization?
    return if Current.account_user&.administrator?

    render json: { error: I18n.t('errors.access_denied') }, status: :forbidden
  end

  def bag_modes
    limits = @current_account.usage_limits[:captain]
    {
      captain_responses: mode_for(limits[:responses], unlimited_without_plan: @current_account.plan.nil?),
      copilot: limits[:copilot][:total_count].nil? ? 'shared' : mode_for(limits[:copilot]),
      internal: mode_for(limits[:internal])
    }
  end

  def mode_for(limits, unlimited_without_plan: false)
    total = limits[:total_count]
    return 'unlimited' if total.nil? || (unlimited_without_plan && total >= ChatwootApp.max_limit)

    total.zero? ? 'not_included' : 'included'
  end
end
