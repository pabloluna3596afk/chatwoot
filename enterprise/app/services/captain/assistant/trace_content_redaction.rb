require 'agents/instrumentation'

module Captain::Assistant::TraceContentRedaction
  include Agents::Instrumentation::Constants

  def on_agent_handoff(from_agent, to_agent, reason, context_wrapper)
    super(from_agent, to_agent, Integrations::LlmInstrumentationHelpers.instrumentation_content(reason), context_wrapper)
  end

  def on_tool_complete(tool_name, result, context_wrapper, error = nil)
    safe_error = RuntimeError.new(error.class.name) if error
    super(tool_name, result, context_wrapper, safe_error)
  end

  private

  def serialize_output(value)
    serialized = super
    Integrations::LlmInstrumentationHelpers.instrumentation_content(serialized)
  end

  def set_run_error_status(root_span, result)
    error = result.error if result.respond_to?(:error)
    return unless error

    root_span.record_exception(RuntimeError.new(error.class.name))
    root_span.status = OpenTelemetry::Trace::Status.error(error.class.name)
  end

  def set_reasoning_summary(span, response, request_attributes)
    return unless request_attributes[:protocol] == :responses
    return unless request_attributes.dig(:thinking, :display).to_s == 'summarized'
    return unless response.respond_to?(:thinking) && response.thinking&.text

    span.set_attribute(ATTR_LANGFUSE_REASONING_SUMMARY,
                       Integrations::LlmInstrumentationHelpers.instrumentation_content(response.thinking.text))
  end
end

Agents::Instrumentation::TracingCallbacks.prepend(Captain::Assistant::TraceContentRedaction)
