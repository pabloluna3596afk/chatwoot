# A server-side candidate tied to one persisted reply and its incoming message.
# Terminal states are retained so a repeated job cannot evaluate the same turn twice.
class Captain::Conversation::CompletionSignal
  KEY = 'captain_completion'.freeze
  ACTIVE_STATUSES = %w[pending evaluating].freeze
  EVALUATION_LEASE = 5.minutes

  def self.cancel(conversation)
    state = conversation.additional_attributes[KEY]
    return unless state && ACTIVE_STATUSES.include?(state['status'])

    conversation.additional_attributes = conversation.additional_attributes.merge(KEY => state.merge('status' => 'cancelled'))
  end

  def initialize(conversation, assistant)
    @conversation = conversation
    @assistant = assistant
  end

  def record(message:, response:, incoming_id:)
    return unless [true, false].include?(response['expects_customer_reply'])

    conversation.with_lock do
      next unless recordable?(message, incoming_id)

      conversation.update!(additional_attributes: conversation.additional_attributes.merge(
        KEY => candidate_attributes(message, response, incoming_id)
      ))
    end
  end

  def review
    retire_interrupted_evaluation
    snapshot = claim
    return unless snapshot.is_a?(Hash)

    result = evaluate
    conversation.with_lock do
      next unless state == snapshot
      next retire('cancelled') unless current_turn?

      Captain::Conversation::ResolutionTransition.perform(conversation, assistant, signal: true) { apply(result) }
    end
  ensure
    Current.reset
  end

  private

  attr_reader :conversation, :assistant

  def recordable?(message, incoming_id)
    eligible? && latest_reply_id == message.id && incoming_id.present? && latest_incoming_id == incoming_id && state['reply_id'] != message.id
  end

  def candidate_attributes(message, response, incoming_id)
    candidate = response['probable_complete'] == true && response['expects_customer_reply'] == false
    {
      'assistant_id' => assistant.id, 'reply_id' => message.id, 'incoming_id' => incoming_id,
      'probable_complete' => response['probable_complete'] == true,
      'expects_customer_reply' => response['expects_customer_reply'], 'status' => candidate ? 'pending' : 'observed',
      'due_at' => (Time.current + assistant.completion_grace_minutes.minutes).utc.iso8601
    }
  end

  def retire_interrupted_evaluation
    conversation.with_lock do
      if state['status'] == 'evaluating' && Time.iso8601(state.fetch('evaluating_at')) + EVALUATION_LEASE <= Time.current
        retire('failed', error: 'evaluation_interrupted')
      end
    end
  end

  def claim
    conversation.with_lock do
      next unless state['status'] == 'pending' && Time.iso8601(state.fetch('due_at')) <= Time.current
      next retire('cancelled') unless assistant && current_turn?

      retire('evaluating', evaluating_at: Time.current.utc.iso8601)
      state.deep_dup
    end
  end

  def state = conversation.additional_attributes.fetch(KEY, {})

  def eligible?
    assistant.reload
    conversation.captain_attended? && conversation.ai_assignee == assistant &&
      conversation.inbox.captain_assistant == assistant && !conversation.inbox.email? && !conversation.inbox.external_bot_active? &&
      assistant.completion_signal_enabled? && assistant.evaluate_inactive_conversations_before_resolving?
  end

  def latest_reply_id = Captain::Conversation::Turn.last_message(conversation)&.id
  def latest_incoming_id = conversation.messages.incoming.maximum(:id)

  def current_turn?
    eligible? && state['assistant_id'] == assistant.id && state['reply_id'] == latest_reply_id && state['incoming_id'] == latest_incoming_id
  end

  def retire(status, **extra)
    attributes = state.merge('status' => status).merge(extra.stringify_keys)
    conversation.update!(additional_attributes: conversation.additional_attributes.merge(KEY => attributes))
  end

  def evaluate
    Captain::ConversationCompletionService.new(account: conversation.account, conversation_display_id: conversation.display_id).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    { complete: false, error: e.class.name }
  end

  def apply(result)
    return retire('failed', error: result[:error].to_s) if result[:error]
    return retire('rejected', expects_customer_reply: result[:expects_customer_reply] == true) unless result[:complete]

    Current.executed_by = assistant
    # No public goodbye and no follow-up/re-engagement mark for a completed request.
    retire('confirmed')
    conversation.update!(additional_attributes: conversation.additional_attributes.except(Captain::Followup::Reengager::STATE_KEY))
    conversation.with_captain_activity_context(reason: result[:reason], reason_type: :inference) { conversation.resolved! }
    Captain::ConversationEvents.resolved(conversation: conversation, assistant: assistant,
                                         source: Captain::ConversationEvents::Sources::INFERENCE, at: Time.current,
                                         reason: result[:customer_confirmed] ? 'customer_confirmation' : 'evaluated_completion')
  end
end
