# Detection is deterministic. Only the existing, installation-funded completion reviewer uses a model.
class Captain::Conversation::LoopGuard
  KEY = 'captain_loop_guard'.freeze
  DEFAULT_REPLIES = 4
  DEFAULT_WINDOW_SECONDS = 180
  PING_PONG_SECONDS = 15
  EVALUATION_LEASE = 5.minutes

  def self.cancel(conversation, cause)
    attributes = conversation.additional_attributes
    loop_state = attributes[KEY]
    return false unless loop_state

    guard = new(conversation, conversation.inbox.captain_assistant)
    guard.cancel_review(loop_state)
    preserve = cause == 'new_incoming' && guard.detected?
    conversation.additional_attributes = if cause == 'new_incoming'
                                           attributes.merge(KEY => loop_state.merge('status' => 'cancelled'))
                                         else
                                           attributes.except(KEY)
                                         end
    preserve
  end

  def initialize(conversation, assistant)
    @conversation = conversation
    @assistant = assistant
  end

  def cancel_review(snapshot)
    record_decision('cancelled', snapshot.fetch('incoming_id')) if snapshot['status'] == 'evaluating'
  end

  def record(message, response)
    @conversation = ::Conversation.find(conversation.id)
    conversation.with_lock do
      history = state['assistant_id'] == assistant.id ? state.fetch('replies', []) : []
      history = history.reject { |item| item['id'] == message.id }
      history << { 'id' => message.id, 'at' => message.created_at.to_f,
                   'complete' => response['probable_complete'] == true, 'expects_reply' => response['expects_customer_reply'] }
      write('assistant_id' => assistant.id, 'replies' => history.last(threshold))
    end
  end

  def detected?
    return false unless assistant && state['assistant_id'] == assistant.id

    replies = recent_replies
    return false if replies.empty?

    messages = recent_messages(replies.first['id'])
    return false unless messages.select(&:outgoing?).map(&:id) == replies.pluck('id')

    repetitive_replies?(replies, messages)
  end

  # True means the response was suppressed, including a duplicate worker for the claimed turn.
  def perform(incoming_id)
    @conversation = ::Conversation.find(conversation.id)
    snapshot = claim(incoming_id)
    return false unless snapshot
    return true if snapshot == :claimed

    result = snapshot['interrupted'] ? { error: :failed } : evaluate
    conversation.with_lock do
      next unless state == snapshot && eligible? && latest_incoming_id == incoming_id

      finish(result, incoming_id)
    end
    true
  end

  private

  attr_reader :conversation, :assistant

  def state = conversation.additional_attributes.fetch(KEY, {})
  def threshold = assistant.config.fetch('loop_guard_replies', DEFAULT_REPLIES)
  def window = assistant.config.fetch('loop_guard_window_seconds', DEFAULT_WINDOW_SECONDS)
  def latest_incoming_id = conversation.messages.captain_response_triggering.maximum(:id)

  def write(attributes)
    conversation.update!(additional_attributes: conversation.additional_attributes.merge(KEY => attributes))
  end

  def eligible?
    conversation.pending? && conversation.assignee_id.nil? && conversation.ai_assignee == assistant &&
      conversation.inbox.reload.captain_assistant == assistant && !conversation.inbox.external_bot_active?
  end

  def recent_replies
    replies = state.fetch('replies', []).last(threshold)
    return [] unless replies.size == threshold && replies.first['at'] >= Time.current.to_f - window

    replies
  end

  def repetitive_replies?(replies, messages)
    closing_replies?(replies) || (replies.none? { |item| item['expects_reply'] == true } && ping_pong?(messages))
  end

  def closing_replies?(replies)
    replies.all? { |item| item['complete'] && item['expects_reply'] == false }
  end

  def recent_messages(first_id)
    conversation.messages.where(private: false, message_type: %i[incoming outgoing])
                .where('id >= ?', first_id).reorder(:id).to_a
  end

  def ping_pong?(messages)
    messages.size >= (threshold * 2) - 1 && messages.each_cons(2).all? do |left, right|
      left.message_type != right.message_type && (right.created_at - left.created_at).between?(0, PING_PONG_SECONDS)
    end
  end

  def claim(incoming_id)
    conversation.with_lock do
      next unless eligible? && latest_incoming_id == incoming_id
      next recover_claim if state['status'] == 'evaluating'
      next unless detected?

      write(state.merge('status' => 'evaluating', 'incoming_id' => incoming_id, 'evaluating_at' => Time.current.to_f))
      record_decision('pending', incoming_id)
      state.deep_dup
    end
  end

  def recover_claim
    return :claimed if state.fetch('evaluating_at') > EVALUATION_LEASE.ago.to_f

    write(state.merge('interrupted' => true))
    state.deep_dup
  end

  def evaluate
    Captain::ConversationCompletionService.new(account: conversation.account, conversation_display_id: conversation.display_id).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    { error: :failed }
  end

  def finish(result, incoming_id)
    status = review_status(result)
    return finalize(status, incoming_id) unless status == 'confirmed'

    applied = Captain::Conversation::ResolutionTransition.perform(conversation, assistant, signal: true) do
      finalize(status, incoming_id)
      true
    end
    finalize('rejected', incoming_id) if !applied && eligible?
  end

  def finalize(status, incoming_id)
    write(state.merge('status' => status))
    record_decision(status, incoming_id)
    note = I18n.t('captain.decisions.loop_guard', locale: conversation.account.locale)
    conversation.messages.create!(account: conversation.account, inbox: conversation.inbox, sender: assistant,
                                  message_type: :outgoing, private: true, content: note)
    status == 'confirmed' ? resolve(note, incoming_id) : handoff
  end

  def review_status(result)
    return 'failed' if result[:error]

    result[:complete] && !assistant.reload.inactive_conversation_resolution_disabled? ? 'confirmed' : 'rejected'
  end

  def resolve(note, incoming_id)
    conversation.update!(additional_attributes: conversation.additional_attributes.except(Captain::Followup::Reengager::STATE_KEY))
    conversation.with_captain_activity_context(reason: note, reason_type: :inference,
                                               decision_key: "loop:#{conversation.id}:#{incoming_id}:confirmed") { conversation.resolved! }
    Captain::ConversationEvents.resolved(conversation: conversation, assistant: assistant,
                                         source: Captain::ConversationEvents::Sources::INFERENCE, at: Time.current,
                                         reason: 'evaluated_completion')
  end

  def handoff
    routing = Captain::HandoffRouter.new(conversation: conversation, assistant: assistant).plan
    conversation.bot_handoff!(routing: routing)
  end

  def record_decision(outcome, incoming_id)
    Captain::Decisions::Recorder.record(
      conversation: conversation, assistant: assistant, decision_key: "loop:#{conversation.id}:#{incoming_id}:#{outcome}",
      anchor_message: conversation.messages.find(incoming_id), kind: 'loop_guard', outcome: outcome, trigger: 'customer_message',
      origin: %w[pending cancelled].include?(outcome) ? 'rule' : 'model',
      parent_decision: conversation.captain_decisions.find_by(decision_key: "loop:#{conversation.id}:#{incoming_id}:pending"),
      reason_code: 'loop_guard', reason_text: I18n.t('captain.decisions.loop_guard', locale: conversation.account.locale),
      evidence: { last_customer_message_id: incoming_id },
      settings_snapshot: { loop_guard_replies: threshold, loop_guard_window_seconds: window }, technical_details: { credits_consumed: 0 }
    )
  end
end
