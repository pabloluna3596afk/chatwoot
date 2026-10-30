module Captain::ChatResponseHelper
  include Integrations::LlmInstrumentationConstants

  private

  def build_response(response)
    Rails.logger.debug { "#{self.class.name} Assistant: #{@assistant.id}, Received response #{response}" }

    parsed = parse_json_response(response.content)
    apply_credit_usage_metadata(parsed)

    persist_message(parsed, 'assistant')
    parsed
  end

  def parse_json_response(content)
    content = content.gsub('```json', '').gsub('```', '')
    content = content.strip
    JSON.parse(content)
  rescue JSON::ParserError => e
    Rails.logger.error "#{self.class.name} Assistant: #{@assistant.id}, Error parsing JSON response: #{e.message}"
    first_json_object(content) || { 'content' => content }
  end

  # Models sometimes emit the same JSON object twice in a row. Keep the first valid
  # one instead of showing the raw text to the agent.
  def first_json_object(content)
    content.split(/(?<=\})\s*(?=\{)/).filter_map do |candidate|
      parsed = JSON.parse(candidate)
      parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end.first
  end

  def apply_credit_usage_metadata(parsed_response)
    return unless captain_v1_assistant?

    OpenTelemetry::Trace.current_span.set_attribute(
      format(ATTR_LANGFUSE_METADATA, 'credit_used'),
      credit_used_for_response?(parsed_response).to_s
    )
  rescue StandardError => e
    Rails.logger.warn "#{self.class.name} Assistant: #{@assistant.id}, Failed to set credit usage metadata: #{e.message}"
  end

  def credit_used_for_response?(parsed_response)
    response = parsed_response['response']

    # The classifier can still decide to hand off after this trace is written.
    # Actual response usage is charged later in ResponseBuilderJob, so billing stays correct.
    response.present? && response != 'conversation_handoff' && parsed_response['action'] != 'handoff'
  end

  def captain_v1_assistant?
    feature_name == 'assistant' && !@assistant.account.feature_enabled?('captain_integration_v2')
  end

  def persist_thinking_message(tool_call)
    return if @copilot_thread.blank?

    tool_name = tool_call.name.to_s

    persist_message(
      {
        'content' => "Using #{tool_name}",
        'function_name' => tool_name,
        'tool_status' => 'in_progress'
      },
      'assistant_thinking'
    )
  end

  def persist_tool_completion(result)
    return if @copilot_thread.blank?

    tool_call = @pending_tool_calls&.pop
    return unless tool_call

    tool_name = tool_call.name.to_s
    status = tool_result_status(result)

    persist_message(
      {
        'content' => status == 'error' ? 'Tool failed' : "Completed #{tool_name}",
        'function_name' => tool_name,
        'tool_status' => status
      },
      'assistant_thinking'
    )
  end

  def persist_pending_tool_errors
    return if @copilot_thread.blank?

    while (tool_call = @pending_tool_calls&.pop)
      persist_message(
        {
          'content' => 'Tool failed',
          'function_name' => tool_call.name.to_s,
          'tool_status' => 'error'
        },
        'assistant_thinking'
      )
    end
  end

  def tool_result_status(result)
    return 'error' if tool_result_error?(result)
    return 'empty' if tool_result_empty?(result)

    'completed'
  end

  def tool_result_error?(result)
    return result.key?(:error) || result.key?('error') if result.is_a?(Hash)

    result.is_a?(String) && result.match?(/\A(?:error|failed|exception)\b/i)
  end

  def tool_result_empty?(result)
    return result.empty? || result.match?(/\A(?:no results|no .+ found)\b/i) if result.is_a?(String)
    return result.empty? || tool_result_total_zero?(result) if result.is_a?(Hash)

    result.nil? || (result.respond_to?(:empty?) && result.empty?)
  end

  def tool_result_total_zero?(result)
    total = result[:total] || result['total']
    total.is_a?(Numeric) && total.zero?
  end
end
