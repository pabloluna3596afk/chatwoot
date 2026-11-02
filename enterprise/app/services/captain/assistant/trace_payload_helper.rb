require_relative 'trace_content_redaction'

module Captain::Assistant::TracePayloadHelper
  private

  def enrich_context_with_trace_payload!(context, message_history, message_to_process)
    context[:captain_v2_trace_input] = serialize_trace_messages(message_history)
    context[:captain_v2_trace_current_input] = serialize_trace_content(message_to_process)
  end

  def serialize_trace_messages(message_history)
    payload = message_history.map do |message|
      {
        role: message[:role].to_s,
        content: trace_content_payload(message[:content])
      }
    end.to_json
    Integrations::LlmInstrumentationHelpers.instrumentation_content(payload)
  end

  def serialize_trace_content(content)
    payload = trace_content_payload(content)
    return '' if payload.blank?

    serialized = payload.is_a?(String) ? payload : payload.to_json
    Integrations::LlmInstrumentationHelpers.instrumentation_content(serialized)
  end

  def trace_content_payload(content)
    case content
    when Array, Hash
      content
    when NilClass
      ''
    else
      content.to_s
    end
  end
end
