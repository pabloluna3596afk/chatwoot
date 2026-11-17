# frozen_string_literal: true

class Whatsapp::MessagePricingSummary
  DEFAULT_MONTHS = 3
  MAX_MONTHS = 12

  PRICING_CATEGORY_SQL = <<~SQL.squish.freeze
    CASE
      WHEN messages.additional_attributes -> 'whatsapp_pricing' ->> 'category' IS NOT NULL
       AND messages.additional_attributes -> 'whatsapp_pricing' ->> 'billable' IN ('true', 'false')
      THEN messages.additional_attributes -> 'whatsapp_pricing' ->> 'category'
    END
  SQL

  PRICING_BILLABLE_SQL = <<~SQL.squish.freeze
    CASE
      WHEN messages.additional_attributes -> 'whatsapp_pricing' ->> 'category' IS NOT NULL
       AND messages.additional_attributes -> 'whatsapp_pricing' ->> 'billable' IN ('true', 'false')
      THEN messages.additional_attributes -> 'whatsapp_pricing' ->> 'billable'
    END
  SQL

  APP_ECHO_SQL = "(messages.content_attributes #>> '{}')::jsonb ->> 'external_echo' = 'true'"

  def initialize(inbox)
    @inbox = inbox
  end

  def perform(months: DEFAULT_MONTHS)
    month_count = valid_month_count(months)
    current_month = Time.zone.now.beginning_of_month
    start_month = current_month - (month_count - 1).months
    summaries = month_range(start_month, current_month).index_with { |month| empty_month(month) }

    grouped_messages(start_month, current_month.next_month).each do |row|
      add_row_to_summary(summaries.fetch(row.month.to_date), row)
    end

    { months: summaries.values.map { |summary| serialize_month(summary) } }
  end

  private

  def valid_month_count(months)
    count = Integer(months, exception: false)
    count&.between?(1, MAX_MONTHS) ? count : DEFAULT_MONTHS
  end

  def month_range(start_month, current_month)
    (0..(((current_month.year * 12) + current_month.month) - ((start_month.year * 12) + start_month.month))).map do |offset|
      (start_month + offset.months).to_date
    end.reverse
  end

  def empty_month(month)
    { month: month.strftime('%Y-%m'), outgoing: 0, with_pricing: 0, app_sent: 0, categories: {} }
  end

  def add_row_to_summary(summary, row)
    count = row.message_count.to_i
    summary[:outgoing] += count

    if priced_row?(row)
      add_priced_row(summary, row, count)
    elsif app_echo?(row.app_echo)
      summary[:app_sent] += count
    end
  end

  def priced_row?(row)
    row.pricing_category.present? && %w[true false].include?(row.pricing_billable)
  end

  def add_priced_row(summary, row, count)
    category = summary[:categories][row.pricing_category] ||= { billable: 0, free: 0 }
    category[row.pricing_billable == 'true' ? :billable : :free] += count
    summary[:with_pricing] += count
  end

  def app_echo?(value)
    value == true || value == 't'
  end

  def serialize_month(summary)
    summary.merge(categories: summary[:categories].map do |category, counts|
      { category: category }.merge(counts)
    end)
  end

  def grouped_messages(start_month, end_month)
    Message.where(account_id: @inbox.account_id, inbox_id: @inbox.id, message_type: :outgoing, private: false)
           .where.not(status: :failed)
           .where(created_at: start_month...end_month)
           .reorder(nil)
           .select(
             'date_trunc(\'month\', messages.created_at) AS month',
             "#{PRICING_CATEGORY_SQL} AS pricing_category",
             "#{PRICING_BILLABLE_SQL} AS pricing_billable",
             "#{APP_ECHO_SQL} AS app_echo",
             'COUNT(*) AS message_count'
           )
           .group('date_trunc(\'month\', messages.created_at)', PRICING_CATEGORY_SQL, PRICING_BILLABLE_SQL, APP_ECHO_SQL)
  end
end
