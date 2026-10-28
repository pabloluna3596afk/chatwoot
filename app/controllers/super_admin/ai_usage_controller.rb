require 'csv'

class SuperAdmin::AiUsageController < SuperAdmin::ApplicationController
  def index
    @month = parsed_month
    @accounts = Account.order(:name)
    @account = Account.find(params[:account_id]) if params[:account_id].present?
    load_dashboard_data
  end

  def message
    @events = AiUsageEvent.where(usage_group_id: params[:usage_group_id]).includes(:account).order(:created_at)
    raise ActiveRecord::RecordNotFound if @events.empty?
  end

  def export
    events = month_events.includes(:account).order(:created_at)
    send_data usage_csv(events), filename: "ai-usage-#{parsed_month.strftime('%Y-%m')}.csv", type: 'text/csv'
  end

  private

  def load_dashboard_data
    @events = month_events.to_a
    @summary = summary_for(@events)
    load_charts
    load_tables
  end

  def load_charts
    @daily_cost = aggregate_cost_by { |event| event.created_at.to_date }
    @daily_calls = @events.group_by { |event| [event.created_at.to_date, event.bucket] }.transform_values(&:size)
    @model_cost = aggregate_cost_by(&:model)
    @calls_per_message = @events.group_by(&:usage_group_id).values.map(&:size).tally.sort.to_h
  end

  def aggregate_cost_by(&)
    @events.group_by(&).transform_values { |rows| rows.sum(&:cost_usd) }
  end

  def load_tables
    @company_ranking = company_ranking(@events)
    @bag_rows = bag_rows(@events)
    @alerts = alerts(@events)
  end

  def company_ranking(events)
    accounts = Account.includes(:plan).where(id: events.map(&:account_id).uniq).index_by(&:id)
    ranking = events.group_by(&:account_id).filter_map do |account_id, rows|
      account = accounts[account_id]
      [account, rows.sum(&:cost_usd)] if account
    end
    ranking.sort_by { |_account, cost| -cost }
  end

  def parsed_month
    Date.strptime(params[:month].presence || Date.current.strftime('%Y-%m'), '%Y-%m')
  rescue Date::Error
    Date.current
  end

  def month_events
    month_start = parsed_month.beginning_of_month.beginning_of_day
    month_end = parsed_month.next_month.beginning_of_month.beginning_of_day
    events = AiUsageEvent.includes(:account).where(created_at: month_start...month_end)
    @account ? events.where(account_id: @account.id) : events
  end

  def usage_csv(events)
    CSV.generate(headers: true) do |csv|
      csv << AiUsageEvent.column_names
      events.each { |event| csv << event.attributes.values }
    end
  end

  def summary_for(events)
    group_sizes = events.group_by(&:usage_group_id).values.map(&:size).sort
    {
      cost: events.sum(&:cost_usd), calls: events.size, messages: group_sizes.size,
      avg_calls: average_calls(group_sizes), p95_calls: percentile_95(group_sizes),
      input_tokens: events.sum(&:input_tokens), output_tokens: events.sum(&:output_tokens),
      plan_cost_percent: plan_cost_percent(events)
    }
  end

  def average_calls(group_sizes)
    group_sizes.any? ? group_sizes.sum.to_f / group_sizes.size : 0
  end

  def percentile_95(values)
    values.empty? ? 0 : values[[(values.length * 0.95).ceil - 1, 0].max]
  end

  def plan_cost_percent(events)
    accounts = Account.includes(:plan).where(id: events.map(&:account_id).uniq)
    plan_total = accounts.sum { |account| account.plan&.price_monthly.to_f }
    plan_total.positive? ? (events.sum(&:cost_usd) / plan_total * 100).round(1) : nil
  end

  def bag_rows(events)
    rows = events.group_by { |event| [event.account_id, event.bucket] }.map do |(account_id, bucket), grouped_events|
      build_bag_row(account_id, bucket, grouped_events)
    end
    rows.sort_by { |row| [row[:account]&.name.to_s, row[:bucket]] }
  end

  def build_bag_row(account_id, bucket, events)
    account = Account.find_by(id: account_id)
    consumed, limit = usage_and_limit(usage_for_month(account), bucket)
    {
      account: account, bucket: bucket, messages: events.map(&:usage_group_id).uniq.size,
      calls: events.size, tokens: events.sum(&:input_tokens) + events.sum(&:output_tokens),
      cost: events.sum(&:cost_usd), consumed: consumed, limit: limit,
      percent: limit.to_i.positive? ? (consumed.to_f / limit * 100).round(1) : nil
    }
  end

  def usage_for_month(account)
    return unless account

    account.account_plan_usages
           .where('period_start < ?', @month.next_month.beginning_of_month)
           .where('period_end >= ?', @month.beginning_of_month)
           .order(period_start: :desc)
           .first
  end

  def usage_and_limit(usage, bucket)
    return [nil, nil] unless usage

    case bucket
    when 'copilot' then copilot_usage_and_limit(usage)
    when 'internal' then [usage.internal_calls_consumed, usage.limit_internal_calls]
    else [usage.responses_consumed, usage.limit_responses]
    end
  end

  def copilot_usage_and_limit(usage)
    return [usage.copilot_responses_consumed, usage.limit_copilot_responses] if usage.limit_copilot_responses

    [usage.copilot_responses_consumed + usage.responses_consumed, usage.limit_responses]
  end

  def alerts(events)
    warnings = (model_alerts(events) + unpriced_alerts(events) + bag_alerts(events) + plan_alerts(events)).uniq
    warnings.each { |warning| Rails.logger.warn("[AI_USAGE] #{warning}") }
    warnings
  end

  def model_alerts(events)
    events.reject { |event| event.model == 'gpt-6-luna' }
          .group_by { |event| [event.model, event.account_id] }
          .values.map do |model_events|
      event = model_events.max_by(&:created_at)
      I18n.t('super_admin.ai_usage.model_alert', model: event.model, account: event.account.name, time: event.created_at)
    end
  end

  def unpriced_alerts(events)
    events.filter_map do |event|
      price = AiModelPrice.current_for(event.model, at: event.created_at)
      next if price && [price.input_per_million, price.cached_input_per_million, price.output_per_million].any?(&:positive?)

      I18n.t('super_admin.ai_usage.unpriced_alert', model: event.model)
    end
  end

  def bag_alerts(events)
    events.map { |event| [event.account_id, event.bucket] }.uniq.filter_map do |account_id, bucket|
      account = Account.find_by(id: account_id)
      consumed, limit = usage_and_limit(usage_for_month(account), bucket)
      next unless limit.to_i.positive? && consumed.to_f / limit >= 0.8

      I18n.t('super_admin.ai_usage.bag_alert', bucket: bucket, account: account&.name,
                                               percent: (consumed.to_f / limit * 100).round)
    end
  end

  def plan_alerts(events)
    threshold = ENV.fetch('AI_USAGE_PLAN_COST_PERCENT', '40').to_f / 100
    events.group_by(&:account_id).filter_map do |account_id, grouped_events|
      plan_alert(account_id, grouped_events, threshold)
    end
  end

  def plan_alert(account_id, events, threshold)
    account = Account.find_by(id: account_id)
    monthly_price = account&.plan&.price_monthly.to_f
    return unless monthly_price.positive? && events.sum(&:cost_usd) > monthly_price * threshold

    I18n.t('super_admin.ai_usage.plan_alert', account: account.name, percent: (threshold * 100).round)
  end
end
