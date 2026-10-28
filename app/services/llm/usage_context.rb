module Llm::UsageContext
  KEY = :llm_usage_context

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

    def with(account:, bucket:, feature:, context: {}, usage_group_id: SecureRandom.uuid)
      previous = current
      ActiveSupport::IsolatedExecutionState[KEY] = {
        account_id: account&.id,
        bucket: bucket.to_s,
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
      return :copilot if feature.match?(/copilot/i)
      return :internal if feature.match?(/assistant_action_classifier|task|internal|embedding|moderation|transcription|content_evaluator/i)

      :captain_responses
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
      tokens = response&.tokens
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

    def token_value(tokens, key)
      return 0 unless tokens

      value = tokens.public_send(key) if tokens.respond_to?(key)
      value.to_i
    end
  end
end
