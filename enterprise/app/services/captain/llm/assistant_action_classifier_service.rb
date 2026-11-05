class Captain::Llm::AssistantActionClassifierService < Llm::BaseAiService
  include Integrations::LlmInstrumentation
  include Captain::Llm::AssistantResponseInspectionHelpers

  def initialize(assistant:, conversation:)
    super(feature: 'assistant', account: conversation.account)
    @assistant = assistant
    @conversation = conversation
    @temperature = 0.0
  end

  def classify(message_history:, assistant_response:)
    return internal_quota_error unless internal_usage_available?

    result = classify_response(message_history, assistant_response)
    result['error'].present? ? release_internal_reservation : finish_internal_reservation
    result
  rescue StandardError => e
    release_internal_reservation
    classification_error_response(e)
  end

  private

  def classify_response(message_history, assistant_response)
    user_prompt = assistant_response_inspection_prompt(
      message_history: message_history,
      assistant_response: assistant_response,
      response_tag: 'assistant_response_to_classify'
    )
    response = generate_classification(user_prompt)
    normalize_response(parse_response(response.content), response.content)
  end

  def generate_classification(user_prompt)
    Llm::UsageContext.with(
      account: @conversation.account,
      bucket: :internal,
      feature: 'assistant_action_classifier',
      context: {
        conversation_id: @conversation.id, reservation_required: internal_reservation_required?,
        required_gate: 'captain_tasks'
      },
      reservation_id: @usage_reservation_id
    ) do
      instrument_llm_call(instrumentation_params(user_prompt)) do
        chat(model: @model, temperature: @temperature)
          .with_schema(Captain::AssistantActionSchema)
          .with_instructions(system_prompt)
          .ask(user_prompt)
      end
    end
  end

  def classification_error_response(error)
    ChatwootExceptionTracker.new(error, account: @conversation.account).capture_exception
    Rails.logger.warn(
      "[CAPTAIN][AssistantActionClassifier] Failed for conversation #{@conversation.display_id}: " \
      "#{error.class.name}: #{error.message}"
    )
    { 'action' => nil, 'action_reason' => nil, 'error' => error.message, 'model' => @model }
  end

  def internal_usage_available?
    @usage_reservation_id = SecureRandom.uuid
    @conversation.account.reserve_captain_ai_usage!(bucket: :internal, reservation_id: @usage_reservation_id)
  end

  def internal_reservation_required?
    account = @conversation.account
    account.current_usage_period.present? && account.usage_limits.dig(:captain, :internal, :total_count).present?
  end

  def release_internal_reservation
    return unless @usage_reservation_id

    @conversation.account.release_captain_ai_usage!(bucket: :internal, reservation_id: @usage_reservation_id)
  end

  def finish_internal_reservation
    return unless @usage_reservation_id

    @conversation.account.finish_captain_ai_usage!(bucket: :internal, reservation_id: @usage_reservation_id)
  end

  def internal_quota_error
    { 'action' => nil, 'error' => I18n.t('captain.internal_limit'), 'model' => @model }
  end

  def normalize_response(parsed, raw_content)
    action = parsed['action'].to_s
    reason = parsed['action_reason'].to_s
    return invalid_response(raw_content) unless Captain::AssistantActionSchema::ACTIONS.include?(action)

    {
      'action' => action,
      'action_reason' => reason.presence,
      'raw_response' => raw_content,
      'model' => @model
    }
  end

  def invalid_response(raw_content)
    {
      'action' => nil,
      'action_reason' => nil,
      'raw_response' => raw_content,
      'error' => 'invalid_classifier_response',
      'model' => @model
    }
  end

  def instrumentation_params(user_prompt)
    {
      span_name: 'llm.captain.assistant_action_classifier',
      model: @model,
      temperature: @temperature,
      account_id: @conversation.account_id,
      conversation_id: @conversation.display_id,
      feature_name: 'assistant_action_classifier',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: user_prompt }
      ],
      metadata: {
        assistant_id: @assistant.id,
        channel_type: @conversation.inbox&.channel_type,
        source: 'v1_response_builder'
      }
    }
  end

  def system_prompt
    Captain::Llm::SystemPromptsService.assistant_action_classifier(
      has_custom_instructions: @assistant.config['instructions'].present?
    )
  end
end
