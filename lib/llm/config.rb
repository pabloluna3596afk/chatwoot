require 'ruby_llm'
require 'agents'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze
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

    def with_api_key(api_key, api_base: nil)
      initialize!
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = api_base
      end

      yield context
    end

    private

    def settings
      InstallationConfig.where(name: SETTING_NAMES).to_h { |config| [config.name, config.value] }
    end

    def configure_ruby_llm(current)
      api_key = current['CAPTAIN_OPEN_AI_API_KEY']
      endpoint = current['CAPTAIN_OPEN_AI_ENDPOINT']
      RubyLLM.configure do |config|
        config.openai_api_key = api_key if api_key.present?
        config.openai_api_base = endpoint.chomp('/') if endpoint.present?
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    def configure_agents(current)
      api_key = current['CAPTAIN_OPEN_AI_API_KEY']
      return if api_key.blank?

      model = current['CAPTAIN_OPEN_AI_MODEL'].presence || LlmConstants::DEFAULT_MODEL
      endpoint = current['CAPTAIN_OPEN_AI_ENDPOINT'] || LlmConstants::OPENAI_API_ENDPOINT
      Agents.configure do |config|
        config.openai_api_key = api_key
        config.openai_api_base = "#{endpoint.chomp('/')}/v1" if endpoint.present?
        config.default_model = model
        config.debug = false
      end
    end
  end
end
