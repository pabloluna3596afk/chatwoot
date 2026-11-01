module Captain::ToolInstrumentation
  extend ActiveSupport::Concern
  include Integrations::LlmInstrumentationConstants

  private

  # Custom instrumentation for tool flows - outputs just the message (not full hash)
  def instrument_tool_session(params)
    return yield unless ChatwootApp.otel_enabled?

    response = nil
    executed = false
    with_propagated_langfuse_attributes(params) do
      tracer.in_span(params[:span_name]) do |span|
        set_tool_session_attributes(span, params)
        response = yield
        executed = true
        output = response[:message] || response.to_json
        span.set_attribute(
          ATTR_LANGFUSE_OBSERVATION_OUTPUT, Integrations::LlmInstrumentationHelpers.instrumentation_content(output)
        )
        set_tool_session_error_attributes(span, response) if response.is_a?(Hash)
      end
    end
    response
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    executed ? response : yield
  end

  def set_tool_session_attributes(span, params)
    set_metadata_attributes(span, params)
    span.set_attribute(
      ATTR_LANGFUSE_OBSERVATION_INPUT,
      Integrations::LlmInstrumentationHelpers.instrumentation_content(params[:messages].to_json)
    )
  end

  def set_tool_session_error_attributes(span, response)
    error = response[:error] || response['error']
    return if error.blank?

    span.set_attribute(ATTR_GEN_AI_RESPONSE_ERROR, '[REDACTED]')
    span.status = OpenTelemetry::Trace::Status.error('Tool execution failed')
  end

  def record_generation(chat, message, model)
    return unless ChatwootApp.otel_enabled?
    return unless message.respond_to?(:role) && message.role.to_s == 'assistant'

    tracer.in_span("llm.#{event_name}.generation") do |span|
      apply_current_langfuse_attributes(span)
      span.set_attribute(ATTR_GEN_AI_PROVIDER, 'openai')
      span.set_attribute(ATTR_GEN_AI_REQUEST_MODEL, model)
      set_generation_usage_attributes(span, message)
      input = Integrations::LlmInstrumentationHelpers.instrumentation_content(format_chat_messages(chat))
      span.set_attribute(ATTR_LANGFUSE_OBSERVATION_INPUT, input)
      next unless message.respond_to?(:content)

      output = Integrations::LlmInstrumentationHelpers.instrumentation_content(message.content)
      span.set_attribute(ATTR_LANGFUSE_OBSERVATION_OUTPUT, output)
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to record generation: #{e.message}"
  end

  def format_chat_messages(chat)
    chat.messages[0...-1].map { |m| { role: m.role.to_s, content: m.content.to_s } }.to_json
  end

  def set_generation_usage_attributes(span, message)
    span.set_attribute(ATTR_GEN_AI_USAGE_INPUT_TOKENS, message.tokens.input) if message.tokens.input
    span.set_attribute(ATTR_GEN_AI_USAGE_OUTPUT_TOKENS, message.tokens.output) if message.tokens.output
  end
end
