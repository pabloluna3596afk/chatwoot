module Captain::Tools::Instrumentation
  extend ActiveSupport::Concern
  include Integrations::LlmInstrumentation
  include Captain::Tools::CopilotToolCallLogging

  def execute(**args)
    context = { started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC), arguments: args,
                limiter: copilot_tool_call_limiter, status: 'ok', attempt: 1 }
    context[:attempt] = context[:limiter]&.consume! || 1
    context[:result] = instrument_tool_call(name, redacted_tool_arguments(args)) { super }
    context[:status] = tool_result_status(context[:result])
    return delimit_untrusted_result(context[:result]) if context[:status] == 'ok'

    context[:result]
  rescue ArgumentError => e
    context[:status] = e.message.include?('tool calls per turn') ? 'denied' : 'error'
    { error: e.message }
  rescue StandardError
    context[:status] = 'error'
    raise
  ensure
    log_tool_call(context) if context
  end
end
