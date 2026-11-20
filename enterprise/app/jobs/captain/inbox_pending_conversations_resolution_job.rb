# rubocop:disable Metrics/ClassLength
class Captain::InboxPendingConversationsResolutionJob < ApplicationJob
  queue_as :low

  def perform(inbox)
    @captain_assistant = inbox.captain_assistant
    return if captain_assistant.blank? || captain_assistant.inactive_conversation_resolution_disabled?

    @inactivity_threshold_minutes = captain_assistant.inactivity_threshold_minutes
    @inactivity_cutoff_time = Time.current - inactivity_threshold_minutes.minutes

    if evaluate_conversation_completion?(inbox.account)
      perform_with_evaluation(inbox)
    else
      perform_time_based(inbox)
    end
  ensure
    Current.reset
  end

  private

  attr_reader :captain_assistant, :inactivity_cutoff_time, :inactivity_threshold_minutes

  def evaluate_conversation_completion?(account)
    account.feature_enabled?('captain_tasks') && captain_assistant.evaluate_inactive_conversations_before_resolving?
  end

  def perform_time_based(inbox)
    Current.executed_by = captain_assistant

    resolvable_pending_conversations(inbox).each do |conversation|
      next handle_unanswered(conversation) if customer_owes_reply?(conversation)

      resolve_time_based_conversation(conversation, inbox)
    end
  end

  def perform_with_evaluation(inbox)
    Current.executed_by = captain_assistant

    resolvable_pending_conversations(inbox).each do |conversation|
      next handle_unanswered(conversation) if customer_owes_reply?(conversation)

      evaluation = evaluate_conversation(conversation, inbox)
      next unless still_resolvable_after_evaluation?(conversation)

      if evaluation[:complete]
        resolve_conversation(conversation, inbox, evaluation[:reason], customer_confirmed: evaluation[:customer_confirmed], evaluation: evaluation)
      else
        handoff_conversation(conversation, evaluation)
      end
    end
  end

  def customer_owes_reply?(conversation)
    return false unless Captain::Conversation::Turn.awaiting_customer?(conversation, captain_assistant)
    return true if captain_assistant.evaluate_inactive_conversations_before_resolving?

    captain_assistant.auto_resolve_mode == 'legacy' && followup_sends_nudges?
  end

  def followup_sends_nudges?
    followup = captain_assistant.followup
    followup.inactivity_enabled? && followup.max_nudges.positive?
  end

  def handle_unanswered(conversation)
    closed = with_unanswered_conversation_lock(conversation) do
      followup = captain_assistant.followup
      next if followup.inactivity_enabled? && followup.max_nudges.positive?

      Captain::Followup::Closer.new(conversation, captain_assistant, note_key: 'captain.notes.closed_unanswered').perform
    end
    return unless closed == :closed

    Captain::ConversationEvents.resolved(conversation: conversation, assistant: captain_assistant,
                                         source: Captain::ConversationEvents::Sources::TIME_BASED, at: Time.current)
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def with_unanswered_conversation_lock(conversation)
    Captain::Conversation::ResolutionTransition.perform(conversation, captain_assistant) do
      conversation.reload
      next unless conversation.captain_attended? && conversation.ai_assignee == captain_assistant
      next unless inactive_for_initial_action?(conversation) && customer_owes_reply?(conversation)

      yield
    end
  end

  def evaluate_conversation(conversation, inbox)
    evaluated_id = Captain::Conversation::Turn.last_message(conversation)&.id
    Captain::ConversationCompletionService.new(
      account: inbox.account,
      conversation_display_id: conversation.display_id
    ).perform.merge(evaluated_through_message_id: evaluated_id).compact
  end

  def resolvable_pending_conversations(inbox)
    inbox.conversations.pending
         .where(assignee_id: nil)
         .where("COALESCE(additional_attributes -> 'captain_completion' ->> 'status', '') NOT IN (?)",
                Captain::Conversation::CompletionSignal::ACTIVE_STATUSES)
         .where('last_activity_at < ?', inactivity_cutoff_time)
         .limit(Limits::BULK_ACTIONS_LIMIT)
  end

  def inactive_for_initial_action?(conversation)
    conversation.assignee_id.blank? && conversation.last_activity_at < inactivity_cutoff_time
  end

  def still_resolvable_after_evaluation?(conversation)
    conversation.reload
    conversation.pending? && inactive_for_initial_action?(conversation)
  rescue ActiveRecord::RecordNotFound
    false
  end

  def resolve_time_based_conversation(conversation, _inbox)
    resolved = false
    Captain::Conversation::ResolutionTransition.perform(conversation, captain_assistant) do
      conversation.reload
      next unless conversation.pending? && inactive_for_initial_action?(conversation)

      create_resolution_message(conversation)
      key = "resolve:time:#{conversation.id}:#{conversation.messages.maximum(:id)}"
      record_inactivity_decision(conversation, key: key, code: 'time_resolve', kind: 'resolve', origin: 'time')
      conversation.with_captain_activity_context(reason: nil, reason_type: :time, decision_key: key) { conversation.resolved! }
      resolved = true
    end
    return unless resolved

    Captain::ConversationEvents.resolved(
      conversation: conversation,
      assistant: captain_assistant,
      source: Captain::ConversationEvents::Sources::TIME_BASED,
      at: Time.current
    )
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def resolve_conversation(conversation, _inbox, reason, customer_confirmed: false, evaluation: {})
    resolved = with_inference_activity_context(conversation, activity_reason(conversation, 'no_outstanding_questions')) do
      perform_locked_transition(conversation) do
        conversation.resolved!
        note = create_private_note(conversation, resolution_note(conversation, reason))
        create_resolution_message(conversation)
        record_inactivity_decision(conversation, key: "resolve:evaluation:#{note.id}", code: 'evaluation_resolve', kind: 'resolve',
                                                 origin: 'model', anchor_message: note, evaluation: evaluation)
      end
    end
    record_inference_resolution(conversation, customer_confirmed: customer_confirmed) if resolved
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def record_inference_resolution(conversation, customer_confirmed: false)
    Captain::ConversationEvents.resolved(
      conversation: conversation,
      assistant: captain_assistant,
      source: Captain::ConversationEvents::Sources::INFERENCE,
      at: Time.current,
      **(customer_confirmed ? { reason: 'customer_confirmation' } : {})
    )
  end

  def handoff_conversation(conversation, evaluation)
    handed_off = with_inference_activity_context(conversation, activity_reason(conversation, 'pending_clarification')) do
      perform_locked_transition(conversation) do
        routing = Captain::HandoffRouter.new(conversation: conversation, assistant: captain_assistant).plan
        conversation.bot_handoff!(dispatch_event: false, routing: routing)
        note = create_private_note(conversation, [handoff_note(conversation, evaluation), routing.note].compact.join("\n"),
                                   captain_handoff: { reason_category: 'pending_clarification', source: 'inference' })
        complete_inactivity_handoff(conversation, note, evaluation)
      end
    end
    return unless handed_off

    conversation.dispatch_bot_handoff_event
    Captain::ConversationEvents.handed_off(
      conversation: conversation, assistant: captain_assistant,
      source: Captain::ConversationEvents::Sources::INFERENCE,
      reason_category: :pending_clarification,
      at: Time.current
    )
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def complete_inactivity_handoff(conversation, note, evaluation)
    create_handoff_message(conversation)
    code = evaluation[:error] ? 'evaluation_error' : 'evaluation_handoff'
    record_inactivity_decision(conversation, key: "handoff:evaluation:#{note.id}", code: code, kind: 'handoff', origin: 'model',
                                             anchor_message: note, evaluation: evaluation)
  end

  def record_inactivity_decision(conversation, key:, code:, kind:, **attributes)
    evaluation = attributes.fetch(:evaluation, {})
    evidence = evaluation.slice(:complete, :customer_confirmed, :expects_customer_reply, :evaluated_through_message_id)
    evidence[:error] = 'evaluation_failed' if evaluation[:error]
    evidence.merge!(action: kind, team_id: conversation.team_id, assignee_id: conversation.assignee_id)
    Captain::Decisions::Action.record(
      conversation: conversation, assistant: captain_assistant, kind: kind, origin: attributes.fetch(:origin),
      trigger: evaluation[:error] ? 'error' : 'inactivity', reason_code: code, decision_key: key, anchor_message: attributes[:anchor_message],
      evidence: evidence.compact, settings_snapshot: { inactivity_threshold_minutes: inactivity_threshold_minutes },
      technical_details: attributes[:origin] == 'model' ? { credits_consumed: 0 } : {}
    )
  end

  def perform_locked_transition(conversation)
    Captain::Conversation::ResolutionTransition.perform(conversation, captain_assistant) do
      conversation.reload
      next false unless conversation.pending? && inactive_for_initial_action?(conversation)

      yield
      true
    end
  end

  def with_inference_activity_context(conversation, reason, &)
    conversation.with_captain_activity_context(reason: reason, reason_type: :inference, &)
  end

  def activity_reason(conversation, key)
    translate(conversation, "captain.activity_reasons.#{key}")
  end

  def resolution_note(conversation, reason)
    return translate(conversation, 'captain.notes.auto_resolved') if reason.blank?

    translate(conversation, 'captain.notes.auto_resolved_with_reason', reason: reason)
  end

  def handoff_note(conversation, evaluation)
    return translate(conversation, 'captain.notes.auto_handoff', reason: evaluation[:reason]) if evaluation[:error].blank?
    return translate(conversation, 'captain.notes.unavailable.missing_key') if evaluation[:error] == :missing_key

    translate(conversation, 'captain.notes.evaluation_failed')
  end

  def translate(conversation, key, **)
    I18n.t(key, assistant: captain_assistant.name, locale: conversation.account.locale, **)
  end

  def create_private_note(conversation, content, content_attributes = {})
    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: captain_assistant,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: content,
      content_attributes: content_attributes
    )
  end

  def create_resolution_message(conversation)
    Captain::Conversation::ResolutionMessageService.new(
      conversation: conversation,
      assistant: captain_assistant
    ).perform(use_default_message: true)
  end

  def create_handoff_message(conversation)
    Captain::Conversation::HandoffReply.new(conversation, captain_assistant).perform
  end
end
# rubocop:enable Metrics/ClassLength
