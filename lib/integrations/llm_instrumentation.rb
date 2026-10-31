# frozen_string_literal: true

require 'opentelemetry_config'
require_relative 'llm_usage_recording'

# rubocop:disable Metrics/ModuleLength
module Integrations::LlmInstrumentation
  include Integrations::LlmInstrumentationConstants
  include Integrations::LlmInstrumentationHelpers
  include Integrations::LlmInstrumentationSpans
  include Integrations::LlmUsageRecording

  def instrument_llm_call(params, &)
    return Llm::UsageContext.with_instrumentation(params) { instrument_llm_call_with_context(params, &) } unless Llm::UsageContext.current

    instrument_llm_call_with_context(params, &)
  end

  # rubocop:disable Metrics/MethodLength
  def instrument_llm_call_with_context(params)
    Llm::MeteringGuard.check!
    provider_called = false
    unless ChatwootApp.otel_enabled?
      provider_called = true
      return yield
    end

    result = nil
    executed = false
    tracer.in_span(params[:span_name]) do |span|
      setup_span_attributes(span, params)
      provider_called = true
      result = yield
      executed = true
      record_completion(span, result)
      result
    end
  rescue StandardError => e
    raise if e.is_a?(Llm::UnmeteredCall)

    ChatwootExceptionTracker.new(e, account: resolve_account(params)).capture_exception
    raise if provider_called && !executed

    executed ? result : yield
  end
  # rubocop:enable Metrics/MethodLength

  def instrument_agent_session(params, &)
    return Llm::UsageContext.with_instrumentation(params) { instrument_agent_session_with_context(params, &) } unless Llm::UsageContext.current

    instrument_agent_session_with_context(params, &)
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
  def instrument_agent_session_with_context(params)
    Llm::MeteringGuard.check!
    provider_called = false
    unless ChatwootApp.otel_enabled?
      provider_called = true
      return yield
    end

    result = nil
    executed = false
    with_propagated_langfuse_attributes(params) do
      tracer.in_span(params[:span_name]) do |span|
        set_metadata_attributes(span, params)

        # By default, the input and output of a trace are set from the root observation
        span.set_attribute(ATTR_LANGFUSE_OBSERVATION_INPUT, '[REDACTED]')
        provider_called = true
        result = yield
        executed = true
        span.set_attribute(ATTR_LANGFUSE_OBSERVATION_OUTPUT, '[REDACTED]')
        set_error_attributes(span, result) if result.is_a?(Hash)
        result
      end
    end
  rescue StandardError => e
    raise if e.is_a?(Llm::UnmeteredCall)

    ChatwootExceptionTracker.new(e, account: resolve_account(params)).capture_exception
    raise if provider_called && !executed

    executed ? result : yield
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength

  def instrument_tool_call(tool_name, _arguments)
    # There is no error handling because tools can fail and LLMs should be
    # aware of those failures and factor them into their response.
    return yield unless ChatwootApp.otel_enabled?

    tracer.in_span(format(TOOL_SPAN_NAME, tool_name)) do |span|
      apply_current_langfuse_attributes(span)
      span.set_attribute(ATTR_LANGFUSE_OBSERVATION_TYPE, 'tool')
      span.set_attribute(ATTR_LANGFUSE_OBSERVATION_INPUT, '[REDACTED]')
      result = yield
      span.set_attribute(ATTR_LANGFUSE_OBSERVATION_OUTPUT, '[REDACTED]')
      set_error_attributes(span, result) if result.is_a?(Hash)
      result
    end
  end

  def instrument_audio_transcription(params)
    return yield unless ChatwootApp.otel_enabled?

    instrument_with_span(params[:span_name] || 'llm.audio.transcription', params) do |span, track_result|
      set_audio_transcription_span_attributes(span, params)
      result = yield
      track_result.call(result)
      set_transcription_result_attributes(span, result)
      result
    end
  end

  private

  def with_usage_recording(params)
    Llm::UsageContext.with_instrumentation(params) do
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = yield
      record_usage_operation(params, response, status: 'ok', started_at: started_at)
      response
    rescue StandardError => e
      record_usage_operation(params, nil, status: 'error', error: e, started_at: started_at)
      raise
    end
  end

  def resolve_account(params)
    return params[:account] if params[:account].is_a?(Account)
    return Account.find_by(id: params[:account_id]) if params[:account_id].present?

    nil
  end
end
# rubocop:enable Metrics/ModuleLength
