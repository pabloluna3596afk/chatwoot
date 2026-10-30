class SuperAdmin::AiUsageAlerts
  def initialize(events, bag_rows)
    @events = events
    @bag_rows = bag_rows
  end

  def call
    warnings = (model_alerts + unpriced_alerts + bag_alerts + plan_alerts + unmapped_alerts).uniq
    warnings.each { |warning| Rails.logger.warn("[AI_USAGE] #{warning}") }
    warnings
  end

  private

  attr_reader :events, :bag_rows

  def unmapped_alerts
    count = events.where(bucket: 'unmapped').count
    return [] if count.zero?

    [I18n.t('super_admin.ai_usage.unmapped_alert', count: count)]
  end

  def model_alerts
    latest_calls = events.where.not(model: 'gpt-6-luna').group(:model, :account_id).maximum(:created_at)
    accounts = Account.where(id: latest_calls.keys.map(&:last).uniq).index_by(&:id)
    latest_calls.filter_map do |(model, account_id), time|
      account = accounts[account_id]
      I18n.t('super_admin.ai_usage.model_alert', model: model, account: account.name, time: time) if account
    end
  end

  def unpriced_alerts
    priced_models = AiModelPrice.where('ai_model_prices.model = ai_usage_events.model')
                                .where(active: true)
                                .where('effective_from <= ai_usage_events.created_at')
                                .where('input_per_million > 0 OR cached_input_per_million > 0 OR output_per_million > 0')
    events.where.not(priced_models.arel.exists).distinct.pluck(:model).map do |model|
      I18n.t('super_admin.ai_usage.unpriced_alert', model: model)
    end
  end

  def bag_alerts
    bag_rows.filter_map do |row|
      next unless row[:limit].to_i.positive? && row[:consumed].to_f / row[:limit] >= 0.8

      I18n.t('super_admin.ai_usage.bag_alert', bucket: row[:bucket], account: row[:account]&.name,
                                               percent: row[:percent].round)
    end
  end

  def plan_alerts
    threshold = ENV.fetch('AI_USAGE_PLAN_COST_PERCENT', '40').to_f / 100
    costs_by_account = events.group(:account_id).sum(:cost_usd)
    accounts = Account.includes(:plan).where(id: costs_by_account.keys).index_by(&:id)
    costs_by_account.filter_map do |account_id, cost|
      account = accounts[account_id]
      monthly_price = account&.plan&.price_monthly.to_f
      next unless monthly_price.positive? && cost > monthly_price * threshold

      I18n.t('super_admin.ai_usage.plan_alert', account: account.name, percent: (threshold * 100).round)
    end
  end
end
