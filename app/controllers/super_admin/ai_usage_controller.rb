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
    @account = Account.find(params[:account_id]) if params[:account_id].present?
    events = month_events.includes(:account).order(:created_at)
    send_data usage_csv(events), filename: "ai-usage-#{parsed_month.strftime('%Y-%m')}.csv", type: 'text/csv'
  end

  private

  def load_dashboard_data
    events = month_events
    @summary = summary_for(events)
    load_charts(events)
    load_tables(events)
    @events = events.includes(:account).order(created_at: :desc).page(params[:page]).per(50)
  end

  def load_charts(events)
    @daily_cost = events.group(Arel.sql('DATE(created_at)')).sum(:cost_usd)
    @daily_calls = events.group(Arel.sql('DATE(created_at)'), :bucket).count
    @model_cost = events.group(:model).sum(:cost_usd)
    @calls_per_message = call_distribution(events)
  end

  def load_tables(events)
    @company_ranking = company_ranking(events)
    @bag_rows = bag_rows(events)
    @alerts = SuperAdmin::AiUsageAlerts.new(events, @bag_rows).call
  end

  def company_ranking(events)
    cost_by_account = events.group(:account_id).sum(:cost_usd)
    accounts = Account.includes(:plan).where(id: cost_by_account.keys).index_by(&:id)
    ranking = cost_by_account.filter_map do |account_id, cost|
      account = accounts[account_id]
      [account, cost] if account
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
    events = AiUsageEvent.where(created_at: month_start...month_end)
    @account ? events.where(account_id: @account.id) : events
  end

  def usage_csv(events)
    CSV.generate(headers: true) do |csv|
      csv << AiUsageEvent.column_names
      events.each { |event| csv << event.attributes.values }
    end
  end

  def summary_for(events)
    cost, calls, input_tokens, output_tokens = events.pick(
      Arel.sql('COALESCE(SUM(cost_usd), 0)'), Arel.sql('COUNT(*)'),
      Arel.sql('COALESCE(SUM(input_tokens), 0)'), Arel.sql('COALESCE(SUM(output_tokens), 0)')
    )
    distribution = call_distribution(events)
    messages = distribution.values.sum
    {
      cost: cost, calls: calls, messages: messages,
      avg_calls: messages.positive? ? distribution.sum { |count, occurrences| count * occurrences }.to_f / messages : 0,
      p95_calls: percentile_95(distribution, messages),
      input_tokens: input_tokens, output_tokens: output_tokens,
      plan_cost_percent: plan_cost_percent(events)
    }
  end

  def call_distribution(events)
    message_calls = events.unscope(:select, :order).group(:usage_group_id).select('COUNT(*) AS call_count')
    AiUsageEvent.from(message_calls, :message_calls).group(:call_count).order(:call_count).count
  end

  def percentile_95(distribution, messages)
    return 0 unless messages.positive?

    percentile_rank = (messages * 0.95).ceil
    distribution.each do |calls, count|
      percentile_rank -= count
      return calls if percentile_rank <= 0
    end
  end

  def plan_cost_percent(events)
    accounts = Account.includes(:plan).where(id: events.distinct.pluck(:account_id))
    plan_total = accounts.sum { |account| account.plan&.price_monthly.to_f }
    total_cost = events.sum(:cost_usd)
    plan_total.positive? ? (total_cost / plan_total * 100).round(1) : nil
  end

  def bag_rows(events)
    aggregates = events.group(:account_id, :bucket).pluck(
      :account_id, :bucket, Arel.sql('COUNT(DISTINCT usage_group_id)'), Arel.sql('COUNT(*)'),
      Arel.sql('SUM(input_tokens + output_tokens)'), Arel.sql('SUM(cost_usd)')
    )
    account_ids = aggregates.map(&:first).uniq
    accounts = Account.where(id: account_ids).index_by(&:id)
    usages = usage_by_account(account_ids)
    aggregate_fields = %i[account_id bucket messages calls tokens cost]
    rows = aggregates.map { |values| build_bag_row(aggregate_fields.zip(values).to_h, accounts, usages) }
    rows.sort_by { |row| [row[:account]&.name.to_s, row[:bucket]] }
  end

  def build_bag_row(aggregate, accounts, usages)
    account = accounts[aggregate[:account_id]]
    usage = usages[aggregate[:account_id]]
    bucket = aggregate[:bucket]
    consumed, limit = usage_and_limit(usage, bucket)
    {
      account: account, bucket: bucket, messages: aggregate[:messages], calls: aggregate[:calls],
      tokens: aggregate[:tokens], cost: aggregate[:cost], consumed: consumed, limit: limit,
      percent: limit.to_i.positive? ? (consumed.to_f / limit * 100).round(1) : nil
    }
  end

  def usage_by_account(account_ids)
    AccountPlanUsage.where(account_id: account_ids)
                    .where('period_start < ? AND period_end >= ?', @month.next_month.beginning_of_month,
                           @month.beginning_of_month)
                    .order(period_start: :desc)
                    .group_by(&:account_id).transform_values(&:first)
  end

  def usage_and_limit(usage, bucket)
    return [nil, nil] unless usage

    case bucket
    when 'copilot' then copilot_usage_and_limit(usage)
    when 'internal' then [usage.internal_calls_consumed, usage.limit_internal_calls]
    when 'captain_responses' then [usage.responses_consumed, usage.limit_responses]
    else [nil, nil]
    end
  end

  def copilot_usage_and_limit(usage)
    return [usage.copilot_responses_consumed, usage.limit_copilot_responses] if usage.limit_copilot_responses

    [usage.copilot_responses_consumed + usage.responses_consumed, usage.limit_responses]
  end
end
