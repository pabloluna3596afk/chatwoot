module Integrations::LlmUsageRecording
  def instrument_embedding_call(params, &)
    with_usage_recording(params) { instrument_embedding_call_with_span(params, &) }
  end

  def instrument_moderation_call(params, &)
    with_usage_recording(params) { instrument_moderation_call_with_span(params, &) }
  end

  private

  def instrument_embedding_call_with_span(params)
    return yield unless ChatwootApp.otel_enabled?

    instrument_with_span(params[:span_name] || 'llm.embedding', params) do |span, track_result|
      set_embedding_span_attributes(span, params)
      result = yield
      track_result.call(result)
      set_embedding_result_attributes(span, result)
      result
    end
  end

  def instrument_moderation_call_with_span(params)
    return yield unless ChatwootApp.otel_enabled?

    instrument_with_span(params[:span_name] || 'llm.moderation', params) do |span, track_result|
      set_moderation_span_attributes(span, params)
      result = yield
      track_result.call(result)
      set_moderation_result_attributes(span, result)
      result
    end
  end

  def with_usage_recording(params)
    Llm::UsageContext.with_instrumentation(params) do
      Llm::MeteringGuard.check!
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = yield
      record_usage_operation(params, response, status: 'ok', started_at: started_at)
      response
    rescue StandardError => e
      record_usage_operation(params, nil, status: 'error', error: e, started_at: started_at)
      raise
    end
  end

  def record_usage_operation(params, response, status:, started_at:, error: nil)
    model = params[:model]
    Llm::UsageContext.record_operation(
      model: model, status: status, provider: params[:provider], response: response,
      error: error,
      latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    )
  end
end
