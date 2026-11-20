class Captain::Decisions::CompletionSignalRecorder
  def initialize(conversation, assistant)
    @conversation = conversation
    @assistant = assistant
  end

  def record(status, snapshot, **facts)
    key = "signal:#{@conversation.id}:#{snapshot['reply_id']}:#{status}"
    Captain::Decisions::Recorder.record(conversation: @conversation, assistant: @assistant, decision_key: key) do
      evidence = snapshot.slice('probable_complete', 'expects_customer_reply').merge('last_customer_message_id' => snapshot.fetch('incoming_id'))
      attributes(status, snapshot).merge(evidence: evidence.merge(facts.stringify_keys))
    end
  end

  private

  def attributes(status, snapshot)
    assistant = @assistant || Captain::Assistant.find_by(id: snapshot['assistant_id'], account_id: @conversation.account_id)
    parent = @conversation.captain_decisions.find_by(decision_key: "signal:#{@conversation.id}:#{snapshot['reply_id']}:pending")
    {
      assistant: assistant, kind: status == 'pending' ? 'completion_signal' : 'completion_review',
      outcome: status, origin: status == 'cancelled' ? 'rule' : 'model', trigger: 'completion_signal',
      reason_code: "signal_#{status}", reason_text: I18n.t("captain.decisions.signal_#{status}", locale: @conversation.account.locale),
      parent_decision: parent,
      anchor_message: @conversation.messages.find_by(id: snapshot['reply_id']), due_at: snapshot['due_at'],
      settings_snapshot: settings_snapshot(status, assistant, parent),
      technical_details: %w[confirmed rejected failed].include?(status) ? { credits_consumed: 0 } : {}
    }
  end

  def settings_snapshot(status, assistant, parent)
    return parent&.settings_snapshot || {} unless status == 'pending'

    { completion_grace_minutes: assistant.completion_grace_minutes }
  end
end
