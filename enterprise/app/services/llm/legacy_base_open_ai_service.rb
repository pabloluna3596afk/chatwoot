# frozen_string_literal: true

# DEPRECATED: This class uses the legacy OpenAI Ruby gem directly.
# Only used for PDF/file operations that require OpenAI's files API:
# - Captain::Llm::PdfProcessingService (files.upload for assistants)
# - Captain::Llm::PaginatedFaqGeneratorService (uses file_id from uploaded files)
#
# For all other LLM operations, use Llm::BaseAiService with RubyLLM instead.
class Llm::LegacyBaseOpenAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL

  attr_reader :client, :model

  def initialize
    @client = OpenAI::Client.new(
      access_token: InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value,
      uri_base: uri_base,
      log_errors: Rails.env.development?
    )
    setup_model
  rescue StandardError => e
    raise "Failed to initialize OpenAI client: #{e.message}"
  end

  private

  def chat(parameters:)
    chat_parameters = parameters.dup
    unless chat_parameters.key?(:reasoning_effort)
      reasoning_effort = Llm::Models.reasoning_effort_for(chat_parameters[:model] || @model)
      chat_parameters[:reasoning_effort] = reasoning_effort if reasoning_effort.present?
    end

    @client.chat(parameters: chat_parameters)
  end

  def log_empty_response(document:, model:, pages:, response:, result:)
    return unless (result['faqs'] || []).empty?

    Rails.logger.warn(
      '[Captain::Llm::PaginatedFaqGeneratorService] Empty FAQ chunk ' \
      "document_id=#{document.id} model=#{model} pages=#{pages.join('-')} " \
      "finish_reason=#{response.dig('choices', 0, 'finish_reason')} " \
      "content_length=#{response.dig('choices', 0, 'message', 'content').to_s.length} " \
      "has_content=#{result['has_content'] != false}"
    )
  end

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def uri_base
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    endpoint.presence || 'https://api.openai.com/'
  end

  def setup_model
    config_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
    @model = (config_value.presence || DEFAULT_MODEL)
  end
end
