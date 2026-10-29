require 'ruby_llm'
require 'agents'
require 'json'

module Llm::Config
  DEFAULT_MODEL = 'gpt-6-luna'.freeze
  SETTING_NAMES = %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_MODEL CAPTAIN_OPEN_AI_ENDPOINT].freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      refresh!
    end

    # RubyLLM and the Agents SDK keep their settings in process memory. Re-applying them whenever
    # the installation settings differ from what this process last applied means a key saved in
    # Super Admin reaches running workers without a restart.
    def refresh!
      current = settings
      return if @initialized && @applied_settings == current

      configure_ruby_llm(current)
      configure_agents(current)
      @applied_settings = current
      @initialized = true
    end

    def reset!
      @initialized = false
      @applied_settings = nil
    end

    def api_key_configured?
      settings['CAPTAIN_OPEN_AI_API_KEY'].present?
    end

    def standard_openai_endpoint?
      endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
      endpoint.blank? || endpoint.chomp('/') == LlmConstants::OPENAI_API_ENDPOINT
    end

    def with_api_key(api_key, api_base: nil)
      initialize!
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = api_base
      end

      yield context
    end

    # The Agents runner builds RubyLLM::Chat directly. Scope those constructors to this request,
    # including handoffs and rewrites.
    # Never mutate global credentials or expose the key in the agent's trace context.
    def with_chat_context(api_key)
      previous = ActiveSupport::IsolatedExecutionState[:llm_chat_context]
      endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || LlmConstants::OPENAI_API_ENDPOINT
      with_api_key(api_key, api_base: "#{endpoint.chomp('/')}/v1") do |context|
        ActiveSupport::IsolatedExecutionState[:llm_chat_context] = context
        yield
      end
    ensure
      ActiveSupport::IsolatedExecutionState[:llm_chat_context] = previous
    end

    private

    def settings
      InstallationConfig.where(name: SETTING_NAMES).to_h { |config| [config.name, config.value] }
    end

    def configure_ruby_llm(current)
      api_key = current['CAPTAIN_OPEN_AI_API_KEY']
      endpoint = current['CAPTAIN_OPEN_AI_ENDPOINT']
      RubyLLM.configure do |config|
        config.openai_api_key = api_key
        api_base = endpoint.presence || LlmConstants::OPENAI_API_ENDPOINT
        config.openai_api_base = "#{api_base.chomp('/')}/v1"
        config.openai_protocol = :chat_completions
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    def configure_agents(current)
      api_key = current['CAPTAIN_OPEN_AI_API_KEY']
      model = current['CAPTAIN_OPEN_AI_MODEL'].presence || LlmConstants::DEFAULT_MODEL
      endpoint = current['CAPTAIN_OPEN_AI_ENDPOINT'].presence || LlmConstants::OPENAI_API_ENDPOINT
      Agents.configure do |config|
        config.openai_api_key = api_key
        config.openai_api_base = "#{endpoint.chomp('/')}/v1" if endpoint.present?
        config.default_model = model
        config.openai_protocol = :chat_completions
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.debug = false
      end
    end
  end
end

module Llm::Config::ScopedChatContext
  def initialize(context: nil, **)
    super(context: context || ActiveSupport::IsolatedExecutionState[:llm_chat_context], **)
  end
end

RubyLLM::Chat.prepend(Llm::Config::ScopedChatContext)

# Record one event per provider request while the caller's account usage context is active.
module Llm::Config::UsageRecordingChat
  def generate_once(stream_tracker: nil, usage_start: nil, &)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = super
    Llm::UsageContext.record(
      chat: self,
      response: response,
      status: 'ok',
      latency_ms: elapsed_milliseconds(started_at)
    )
    response
  rescue StandardError => e
    Llm::UsageContext.record(
      chat: self,
      response: error_usage_response(e),
      status: 'error',
      error: e,
      latency_ms: elapsed_milliseconds(started_at)
    )
    raise
  end

  private

  def error_usage_response(error)
    response = error.response if error.respond_to?(:response)
    return response if response.respond_to?(:tokens)

    usage = error_usage(error)
    return unless usage

    Struct.new(:tokens).new(error_tokens(usage))
  rescue StandardError
    nil
  end

  def error_usage(error)
    response = error.response if error.respond_to?(:response)
    body = response.respond_to?(:body) ? response.body : response
    payload = body.is_a?(String) ? JSON.parse(body) : body
    payload&.dig('usage') || payload&.dig(:usage)
  rescue StandardError
    nil
  end

  def error_tokens(usage)
    input_details = usage_value(usage, 'prompt_tokens_details', 'input_tokens_details') || {}
    output_details = usage_value(usage, 'completion_tokens_details', 'output_tokens_details') || {}
    Struct.new(:input, :output, :cached_input, :reasoning).new(
      usage_value(usage, 'prompt_tokens', 'input_tokens'),
      usage_value(usage, 'completion_tokens', 'output_tokens'),
      usage_value(input_details, 'cached_tokens') || 0,
      usage_value(output_details, 'reasoning_tokens') || 0
    )
  end

  def usage_value(usage, *keys)
    keys.lazy.map { |key| usage[key] || usage[key.to_sym] }.find(&:itself)
  end

  def elapsed_milliseconds(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end
end

RubyLLM::Chat.prepend(Llm::Config::UsageRecordingChat)

# OpenAI rejects function tools on chat completions for models that default to reasoning, so
# config/llm.yml pins `reasoning_effort` per model. RubyLLM replaces provider options on every
# `with_provider_options` call, so the pinned effort is re-merged each time instead of set once.
module Llm::Config::PinnedReasoningEffort
  def initialize(*, **)
    super
    with_provider_options({})
  end

  def with_provider_options(provider_options)
    effort = Llm::Models.reasoning_effort_for(model&.id)
    pinned = effort ? { reasoning_effort: effort } : {}
    super(pinned.merge(provider_options.to_h.symbolize_keys))
  end
end

RubyLLM::Chat.prepend(Llm::Config::PinnedReasoningEffort)
