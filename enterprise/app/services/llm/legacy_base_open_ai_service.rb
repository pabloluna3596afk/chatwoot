# frozen_string_literal: true

# DEPRECATED: This class uses the legacy OpenAI Ruby gem directly.
# Only used for OpenAI APIs that need the legacy client:
# - PDF upload and deletion in Captain::Llm::PdfProcessingService
# - File-backed Responses in Captain::Llm::PaginatedFaqGeneratorService
# - Audio transcription in Llm::SpeechToTextService
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

  def log_empty_response(document:, model:, pages:, response:, result:)
    return unless (result['faqs'] || []).empty?

    Rails.logger.warn(
      '[Captain::Llm::PaginatedFaqGeneratorService] Empty FAQ chunk ' \
      "document_id=#{document.id} model=#{model} pages=#{pages.join('-')} " \
      "finish_reason=#{response.dig('choices', 0, 'finish_reason') || response['status']} " \
      "content_length=#{(response.dig('choices', 0, 'message', 'content') || response.dig('output', 0, 'content', 0, 'text')).to_s.length} " \
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
