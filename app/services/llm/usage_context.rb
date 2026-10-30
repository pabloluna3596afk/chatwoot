module Llm::UsageTokenAttributes
  extend self

  NESTED_DETAILS = {
    cached_input: [[:input_tokens_details, :cached_tokens], [:prompt_tokens_details, :cached_tokens]],
    reasoning: [[:completion_tokens_details, :reasoning_tokens]]
  }.freeze

  def call(model:, response:)
    tokens = response_detail(response, :tokens) || response_detail(response, :usage)
    tokens ||= response['usage'] || response[:usage] if response.is_a?(Hash)
    input_tokens = token_value(tokens, :input)
    cached_tokens = token_value(tokens, :cached_input)
    output_tokens = token_value(tokens, :output)
    {
      input_tokens: input_tokens, cached_input_tokens: cached_tokens,
      output_tokens: output_tokens, reasoning_tokens: token_value(tokens, :reasoning),
      cost_usd: AiUsageEvent.calculate_cost(
        model: model, input_tokens: input_tokens, cached_input_tokens: cached_tokens,
        output_tokens: output_tokens
      )
    }
  end

  private

  def token_value(tokens, key)
    return 0 unless tokens

    aliases = {
      input: %i[input prompt_tokens input_tokens],
      cached_input: %i[cached_input cached_input_tokens cached_tokens],
      output: %i[output completion_tokens output_tokens],
      reasoning: %i[reasoning reasoning_tokens]
    }
    value = aliases.fetch(key).lazy.filter_map { |name| token_detail(tokens, name) }.first
    value ||= nested_token_detail(tokens, key)
    value.to_i
  end

  def nested_token_detail(tokens, key)
    NESTED_DETAILS.fetch(key, []).lazy.filter_map do |container, detail|
      details = token_detail(tokens, container)
      token_detail(details, detail) if details
    end.first
  end

  def response_detail(response, key)
    response.public_send(key) if response.respond_to?(key)
  rescue StandardError
    nil
  end

  def token_detail(tokens, key)
    return tokens.public_send(key) if tokens.respond_to?(key)
    return tokens[key] || tokens[key.to_s] if tokens.is_a?(Hash)
  end
end

module Llm::UsageContext
  KEY = :llm_usage_context

  FEATURE_BUCKETS = {
    'assistant_action_classifier' => :internal,
    'assistant_false_promise_detector' => :internal,
    'assistant_migration_instruction_auditor' => :internal,
    'assistant_migration_instruction_classifier' => :internal,
    'article_translation' => :captain_responses,
    'article_writer' => :captain_responses,
    'assistant' => :captain_responses,
    'assistant_playground' => :captain_responses,
    'audio_transcription' => :captain_responses,
    'captain.conversation_completion' => :internal,
    'captain_assistant_overview_summary' => :internal,
    'captain_overview_summary' => :internal,
    'captain_reply' => :captain_responses,
    'contact_attributes' => :captain_responses,
    'contact_notes' => :captain_responses,
    'content_evaluator' => :internal,
    'conversation_faq' => :captain_responses,
    'conversation_faq_match' => :captain_responses,
    'copilot' => :copilot,
    'copilot_reply' => :copilot,
    'copilot_reply_suggestion' => :copilot,
    'csat_utility_analysis' => :internal,
    'document_faq_generation' => :captain_responses,
    'embedding' => :internal,
    'faq_generation' => :captain_responses,
    'faq_generator' => :captain_responses,
    'follow_up' => :internal,
    'help_center_article_generation' => :captain_responses,
    'help_center_curation' => :captain_responses,
    'help_center_query_translation' => :captain_responses,
    'improve' => :internal,
    'label_suggestion' => :internal,
    'language_detection' => :captain_responses,
    'message_translation' => :captain_responses,
    'onboarding_content_generation' => :captain_responses,
    'paginated_faq_generation' => :captain_responses,
    'professional' => :internal,
    'casual' => :internal,
    'friendly' => :internal,
    'confident' => :internal,
    'straightforward' => :internal,
    'fix_spelling_grammar' => :internal,
    'reply_suggestion' => :internal,
    'summary' => :internal,
    'summarize' => :internal,
    'translate_query' => :captain_responses,
    'website_analyzer' => :captain_responses,
    'widget_tagline' => :captain_responses
  }.freeze

  class << self
    def current
      ActiveSupport::IsolatedExecutionState[KEY]
    end

    def with_instrumentation(params, &)
      return yield if current

      feature = params[:feature_name].presence || 'unknown'
      account = resolve_account(params)
      return yield unless account

      conversation_id = resolve_conversation_id(account, params[:conversation_id])
      with(account: account, bucket: bucket_for(feature), feature: feature,
           context: { conversation_id: conversation_id }, &)
    end

    def with(account:, feature:, bucket: nil, context: {}, usage_group_id: SecureRandom.uuid)
      mapped_bucket = bucket_for(feature.to_s)
      if bucket.present? && bucket.to_sym != mapped_bucket
        raise ArgumentError, "AI usage bucket mismatch for #{feature}: #{bucket} != #{mapped_bucket}"
      end

      previous = current
      ActiveSupport::IsolatedExecutionState[KEY] = {
        account_id: account&.id,
        bucket: mapped_bucket.to_s,
        feature: feature.to_s,
        usage_group_id: usage_group_id
      }.merge(context)
      yield usage_group_id
    ensure
      ActiveSupport::IsolatedExecutionState[KEY] = previous
    end

    def record(chat:, response:, status:, error: nil, latency_ms: nil)
      record_operation(
        model: chat.model&.id, status: status, provider: chat.model&.provider,
        response: response, error: error, latency_ms: latency_ms
      )
    end

    def record_operation(model:, status:, **details)
      context = current
      return unless context&.dig(:account_id)

      record_event(model: model, context: context, details: details.merge(status: status))
    rescue StandardError => e
      Rails.logger.warn("Failed to record AI usage: #{e.class}: #{e.message}")
    end

    private

    def bucket_for(feature)
      FEATURE_BUCKETS.fetch(feature) do
        raise ArgumentError, "Unmapped AI usage feature: #{feature}"
      end
    end

    def resolve_account(params)
      params[:account] || Account.find_by(id: params[:account_id])
    rescue StandardError => e
      Rails.logger.warn("Failed to establish AI usage context: #{e.class}: #{e.message}")
      nil
    end

    def resolve_conversation_id(account, display_id)
      account.conversations.find_by(display_id: display_id)&.id if display_id.present?
    rescue StandardError => e
      Rails.logger.warn("Failed to resolve AI usage conversation: #{e.class}: #{e.message}")
      nil
    end

    def record_event(model:, context:, details:)
      response = details[:response]
      AiUsageEvent.create!(context.except(:account_id).merge(
                             event_identity(model, context, details, response),
                             token_attributes(model, response),
                             status: details[:status], error_class: details[:error]&.class&.name,
                             latency_ms: details[:latency_ms], created_at: Time.current
                           ))
    end

    def event_identity(model, context, details, response)
      model_provider = details[:provider].presence || provider_for(model, response)
      { account_id: context[:account_id], model: model.to_s, provider: model_provider.to_s.presence || 'unknown' }
    end

    def provider_for(model, response)
      if response.respond_to?(:ruby_llm_usage_entries)
        response.ruby_llm_usage_entries.last&.provider
      elsif response.respond_to?(:model_info)
        response.model_info&.provider
      else
        RubyLLM.models.find(model.to_s).provider
      end
    end

    def token_attributes(model, response)
      Llm::UsageTokenAttributes.call(model: model, response: response)
    end
  end
end
