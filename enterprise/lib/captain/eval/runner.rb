require 'timeout'

class Captain::Eval::Runner
  CASE_TIMEOUT = 90
  class Refused < StandardError; end

  def initialize(env: ENV)
    @env = env
  end

  def perform
    guard!
    suite = Captain::Eval::Suite.new(names: @env['CASES'])
    repeat = Integer(@env.fetch('REPEAT', '1'), 10)
    raise ArgumentError, 'REPEAT debe ser positivo' unless repeat.positive?

    with_distance do
      sandbox = Captain::Eval::Sandbox.new.prepare(pilot: @env['PILOT'] == '1')
      started_at = Time.current
      results = run_suite(suite, sandbox, repeat)
      Captain::Eval::Report.new(results: results, account: sandbox.account, started_at: started_at,
                                settings: { pilot: Captain::Pilot.enabled?(sandbox.account), repeat: repeat,
                                            max_distance: Captain::Knowledge::Relevance.max_distance }).write
    end
  end

  private

  def guard!
    raise Refused, 'Requiere CAPTAIN_EVAL=1' unless @env['CAPTAIN_EVAL'] == '1'
    raise Refused, 'La evaluación solo se permite en desarrollo o en specs simulados' unless allowed_environment?
    raise Refused, 'La evaluación no se permite en CI' if @env['CI'].present?
    raise Refused, 'No hay clave de IA configurada' unless Llm::Config.api_key_configured?
  end

  def allowed_environment?
    Rails.env.development? || (Rails.env.test? && defined?(RSpec) && RSpec.current_example.present?)
  end

  def with_distance
    return yield unless @env['MAX_DISTANCE']

    value = Float(@env['MAX_DISTANCE'])
    raise ArgumentError, 'MAX_DISTANCE debe estar entre 0.20 y 1.00' unless Captain::Knowledge::Relevance::RANGE.cover?(value)

    config = InstallationConfig.find_or_initialize_by(name: Captain::Knowledge::Relevance::CONFIG_NAME)
    previous = config.serialized_value.deep_dup
    existed = config.persisted?
    begin
      config.update!(value: value)
      yield
    ensure
      existed ? config.update!(serialized_value: previous) : config.destroy!
    end
  end

  def run_suite(suite, sandbox, repeat)
    suite.verticals.flat_map do |vertical|
      assistant = sandbox.assistant_for(vertical)
      vertical.fetch('cases').map do |item|
        attempts = Array.new(repeat) { run_case(item, assistant, sandbox) }
        { id: item.fetch('id'), title: item.fetch('title'), vertical: vertical.fetch('vertical'),
          type: item.fetch('id').split('-').last, passed: attempts.all? { |attempt| attempt[:passed] }, attempts: attempts }
      end
    end
  end

  def run_case(item, assistant, sandbox)
    responses = []
    tools = []
    Timeout.timeout(CASE_TIMEOUT) do
      conversation = sandbox.conversation_for(item.fetch('id'))
      response, completed_handoff = run_turns(item, assistant, sandbox, conversation, { tools: tools, responses: responses })
      handoff = completed_handoff && conversation.reload.open?
      checks = Captain::Eval::Checks.new(response: response, tools: tools, handoff: handoff).perform(item.fetch('expect'))
      { passed: checks.all? { |check| check[:passed] }, checks: checks, response: response,
        responses: responses, tools: tools.uniq, handoff: handoff }
    end
  rescue StandardError => e
    { passed: false, error: "#{e.class}: #{e.message}", response: responses.last.to_s, responses: responses, tools: tools.uniq }
  end

  def run_turns(item, assistant, sandbox, conversation, observation)
    options = Captain::Assistant::AgentRunnerService::RunOptions.new(
      callbacks: { on_tool_start: ->(name, *_args) { observation[:tools] << name.to_s.split('--').last } }
    )
    handoff = false
    item.fetch('turns').each do |turn|
      sandbox.add_message(conversation, content: turn, sender: conversation.contact, message_type: :incoming)
      response, runner = generate_turn(assistant, conversation, options)
      observation[:responses] << response.fetch('response')
      raise response.fetch('reasoning') if response['error']

      sandbox.add_message(conversation, content: observation[:responses].last, sender: assistant, message_type: :outgoing)
      handoff ||= handoff_completed?(runner)
    end
    [observation[:responses].last, handoff]
  end

  def generate_turn(assistant, conversation, options)
    runner = Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: conversation, run_options: options)
    history = Captain::Conversation::MessageHistoryBuilderService.new(conversation: conversation).perform
    response = Llm::UsageContext.with(account: assistant.account, feature: 'captain_reply', context: { conversation_id: conversation.id }) do
      runner.generate_response(message_history: history)
    end
    [response, runner]
  end

  def handoff_completed?(runner)
    runner.last_run_result&.context&.dig(:captain_v2_handoff_tool_called) == true && runner.handoff_completed?
  end
end
