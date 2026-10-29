module Captain::Tools::CopilotToolCallLogging
  SAFE_CATEGORY_VALUES = {
    'order_by' => %w[last_activity_at created_at],
    'direction' => %w[asc desc],
    'resource' => %w[conversations contacts],
    'group_by' => %w[status priority inbox assignee team label country blocked day week month year]
  }.freeze

  private

  def redacted_tool_arguments(arguments)
    arguments.each_with_object({}) do |(key, value), safe|
      key = key.to_s
      safe[key] = value if safe_category?(key, value)
      safe["#{key}_present"] = true if value.present? && !safe.key?(key)
    end
  end

  def safe_category?(key, value)
    return Conversation.statuses.key?(value) if key == 'status'
    return Conversation.priorities.key?(value) if key == 'priority'
    return value.is_a?(Integer) && value.between?(1, 100) if key == 'limit'

    SAFE_CATEGORY_VALUES[key]&.include?(value) || false
  end

  def delimit_untrusted_result(result)
    return result unless %w[search_conversation get_conversation search_contacts get_contact].include?(name.to_s)
    return result unless result.is_a?(String) && result.present?

    "UNTRUSTED_DATA_BEGIN\n#{result}\nUNTRUSTED_DATA_END"
  end

  def tool_result_status(result)
    return 'error' if result.is_a?(Hash) && result.key?(:error)
    return 'empty' if result.is_a?(String) && result.match?(/\A(?:No |Conversation not found|Contact not found|Article not found)/)

    'ok'
  end

  def log_tool_call(context)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - context[:started_at]) * 1000).round
    attributes = tool_call_log_attributes(context).merge(duration_ms: elapsed)
    Rails.logger.info(attributes.to_json)
  end

  def tool_call_log_attributes(context)
    arguments = context[:arguments]
    context.slice(:attempt).merge(
      result: context[:status], event: 'copilot_tool_call', tool_name: name, turn_id: context[:limiter]&.turn_id,
      filter_names: filter_names(arguments), filter_values: safe_filter_values(arguments),
      order_by: arguments[:order_by], direction: arguments[:direction]
    ).merge(tool_result_counts(context[:result], context[:status]))
  end

  def tool_result_counts(result, status)
    return { returned_count: 0, total_count: 0, truncated: false } if status == 'empty'
    return { returned_count: result.length, total_count: result.length, truncated: false } if result.is_a?(Array)
    return counts_from_hash(result) if result.is_a?(Hash) && !result.key?(:error)

    counts_from_text(result)
  end

  def counts_from_hash(result)
    count = result[:total] || result[:custom_attributes]&.length || result[:groups]&.length
    return {} unless count

    { returned_count: count, total_count: count, truncated: false }
  end

  def counts_from_text(result)
    return {} unless result.is_a?(String)

    total = extract_total_count(result)
    returned = extract_returned_count(result)
    returned ||= result.split("\n---\n").length if result.present?
    total ||= returned
    { returned_count: returned, total_count: total, truncated: total.present? && returned.present? && total > returned }
  end

  def extract_total_count(result)
    count_from_match(result, /Found (\d+) (?:conversations|contacts|articles)/) ||
      count_from_match(result, /Total number of (?:conversations|contacts|articles): (\d+)/)
  end

  def extract_returned_count(result)
    count_from_match(result, /showing first (\d+)/)
  end

  def count_from_match(result, pattern)
    result.match(pattern)&.captures&.first&.to_i
  end

  def filter_names(arguments)
    nested_filters = arguments[:filters].is_a?(Hash) ? arguments[:filters].keys.map(&:to_s) : []
    direct_filters = arguments.keys.map(&:to_s) - %w[order_by direction limit status priority resource group_by aggregate]
    (nested_filters + direct_filters).uniq.sort
  end

  def safe_filter_values(arguments)
    filters = arguments[:filters].is_a?(Hash) ? arguments[:filters].stringify_keys : {}
    values = arguments.slice(:status, :priority).stringify_keys.merge(filters.slice('status', 'priority'))
    values.select { |key, value| safe_category?(key, value) }
  end
end
