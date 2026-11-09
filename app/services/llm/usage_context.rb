module Llm::UsageTokenAttributes
  extend self

  NESTED_DETAILS = {
    cached_input: [[:input_tokens_details, :cached_tokens], [:prompt_tokens_details, :cached_tokens]],
    reasoning: [[:completion_tokens_details, :reasoning_tokens], [:output_tokens_details, :reasoning_tokens]]
  }.freeze

  def call(model:, response:, audio_duration_seconds: nil)
    tokens = response_detail(response, :tokens) || response_detail(response, :usage)
    tokens ||= response['usage'] || response[:usage] if response.is_a?(Hash)
    input_tokens = total_input_tokens(tokens)
    cached_tokens = token_value(tokens, :cached_input)
    output_tokens = token_value(tokens, :output)
    {
      input_tokens: input_tokens, cached_input_tokens: cached_tokens,
      output_tokens: output_tokens, reasoning_tokens: token_value(tokens, :reasoning),
      cost_usd: AiUsageEvent.calculate_cost(
        model: model, input_tokens: input_tokens, cached_input_tokens: cached_tokens,
        output_tokens: output_tokens
      ) + AiUsageEvent.calculate_audio_cost(model: model, duration_seconds: audio_duration_seconds),
      audio_duration_seconds: audio_duration_seconds
    }
  end

  private

  def token_value(tokens, key)
    return 0 unless tokens

    aliases = {
      input: %i[input prompt_tokens input_tokens],
      cached_input: %i[cached_input cached_input_tokens cached_tokens cache_read cache_read_tokens],
      cache_read: %i[cache_read cache_read_tokens],
      cache_write: %i[cache_write cache_write_tokens],
      output: %i[output completion_tokens output_tokens],
      reasoning: %i[reasoning reasoning_tokens thinking thinking_tokens]
    }
    value = aliases.fetch(key).lazy.filter_map { |name| token_detail(tokens, name) }.first
    value ||= nested_token_detail(tokens, key)
    value.to_i
  end

  # RubyLLM 2.x separates cache reads and writes from standard input. Our cost
  # calculation expects total input, with cache reads as a subset of that total.
  def total_input_tokens(tokens)
    input_tokens = token_value(tokens, :input)
    return input_tokens unless ruby_llm_token_buckets?(tokens)

    input_tokens + token_value(tokens, :cache_read) + token_value(tokens, :cache_write)
  end

  def ruby_llm_token_buckets?(tokens)
    tokens.respond_to?(:cache_read) || token_detail(tokens, :cache_read_tokens)
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

# rubocop:disable Metrics/ModuleLength
module Llm::UsageContext
  # Shared context construction deliberately stays together with its feature map boundary.
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

      begin
        mapped_bucket = bucket_for(feature)
      rescue ArgumentError => e
        raise Llm::UnmeteredCall, e.message if Rails.env.test? || ENV['CI'].present?

        Rails.logger.error("Unmapped AI usage feature #{feature}: #{e.message}")
        return with_unmapped_bucket(account, feature, params, &)
      end

      conversation_id = resolve_conversation_id(account, params[:conversation_id])
      message_id = resolve_message_id(account, params[:message_id])
      with(account: account, bucket: mapped_bucket, feature: feature,
           context: { conversation_id: conversation_id, message_id: message_id }, &)
    end

    # Keep the public block API explicit for callers that scope provider work.
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
    def with(account:, feature:, bucket: nil, context: {}, reservation_id: nil, usage_group_id: SecureRandom.uuid,
             units: 1)
      begin
        mapped_bucket = bucket_for(feature.to_s)
      rescue ArgumentError => e
        raise Llm::UnmeteredCall, e.message if Rails.env.test? || ENV['CI'].present?

        Rails.logger.error(e.message)
        mapped_bucket = :unmapped
      end
      if bucket.present? && bucket.to_sym != mapped_bucket
        message = "AI usage bucket mismatch for #{feature}: #{bucket} != #{mapped_bucket}"
        raise Llm::UnmeteredCall, message if Rails.env.test? || ENV['CI'].present?

        Rails.logger.error(message)
        mapped_bucket = :unmapped
      end

      previous = current
      ActiveSupport::IsolatedExecutionState[KEY] = {
        account_id: account&.id,
        bucket: mapped_bucket.to_s,
        feature: feature.to_s,
        usage_group_id: usage_group_id,
        reservation_id: reservation_id,
        units: units,
        required_plan: account&.plan&.slug
      }.merge(context)
      yield usage_group_id
    ensure
      ActiveSupport::IsolatedExecutionState[KEY] = previous
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity

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

    def bucket_for(feature)
      Llm::UsageFeatureBuckets::FEATURE_BUCKETS.fetch(feature) do
        raise ArgumentError, "Unmapped AI usage feature: #{feature}"
      end
    end

    private

    def with_unmapped_bucket(account, feature, params)
      previous = current
      ActiveSupport::IsolatedExecutionState[KEY] = {
        account_id: account.id, bucket: 'unmapped', feature: feature,
        usage_group_id: SecureRandom.uuid, required_plan: account.plan&.slug,
        required_gate: params[:required_gate]
      }
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[KEY] = previous
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

    def resolve_message_id(account, message_id)
      account.messages.find_by(id: message_id)&.id if message_id.present?
    rescue StandardError => e
      Rails.logger.warn("Failed to resolve AI usage message: #{e.class}: #{e.message}")
      nil
    end

    def record_event(model:, context:, details:)
      response = details[:response]
      event_context = context.except(
        :account_id, :reservation_id, :reservation_required, :required_gate, :required_plan, :units,
        :audio_duration_seconds
      )
      AiUsageEvent.create!(event_context.merge(
                             event_identity(model, context, details, response),
                             token_attributes(model, response, context[:audio_duration_seconds]),
                             units: context.fetch(:units, 1),
                             extra_units: reservation_extra_units(context),
                             status: details[:status], error_class: details[:error]&.class&.name,
                             latency_ms: details[:latency_ms], created_at: Time.current
                           ))
    end

    def reservation_extra_units(context)
      return 0 unless context[:reservation_id]

      reservation = AiUsageReservation.joins(:account_plan_usage).find_by(
        reservation_id: context[:reservation_id], bucket: context[:bucket],
        account_plan_usages: { account_id: context[:account_id] }
      )
      reservation ? reservation.extra_allocations.values.sum : 0
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

    def token_attributes(model, response, audio_duration_seconds)
      Llm::UsageTokenAttributes.call(
        model: model, response: response, audio_duration_seconds: audio_duration_seconds
      )
    end
  end
end
# rubocop:enable Metrics/ModuleLength
