# Called inside the effective follow-up action's conversation lock and transaction.
class Captain::Decisions::FollowupRecording
  def initialize(conversation, assistant, now: Time.current)
    @conversation = conversation
    @assistant = assistant
    @now = now
  end

  def close(note, turn, inactivity_threshold_minutes:)
    record(note, 'close_unanswered', turn&.id || note.id) do
      evidence = close_evidence(turn)
      { reason_code: 'followup_close', evidence: evidence,
        settings_snapshot: { 'inactivity_threshold_minutes' => inactivity_threshold_minutes },
        reason_text: reason('followup_close', minutes: inactivity_threshold_minutes, count: evidence.fetch('nudges_sent')) }
    end
  end

  def nudge(message, turn, attempt)
    record(message, 'nudge', "#{turn.id}:#{attempt}") do
      { reason_code: 'followup_nudge', evidence: { 'nudge_attempt' => attempt, 'evaluated_through_message_id' => turn.id },
        settings_snapshot: { 'inactivity_after_minutes' => assistant.followup.inactivity_after_minutes,
                             'max_nudges' => assistant.followup.max_nudges },
        reason_text: reason('followup_nudge', attempt: attempt, minutes: assistant.followup.inactivity_after_minutes,
                                              max: assistant.followup.max_nudges) }
    end
  end

  def reengage(anchor, closed_at, result)
    record(anchor, 'reengage', closed_at, outcome: result.fetch('status') == 'sent' ? 'created' : 'skipped') do
      code = "reengage_#{result['reason'] || 'sent'}"
      { reason_code: code, reason_text: I18n.t("captain.decisions.#{code}", locale: conversation.account.locale) }
    end
  end

  private

  attr_reader :conversation, :assistant, :now

  def close_evidence(turn)
    nudges = nudges_after(turn)
    last_activity = nudges.map(&:created_at).max || turn&.created_at
    evidence = { 'nudges_sent' => nudges.size }
    evidence['evaluated_through_message_id'] = turn.id if turn
    evidence['wait_seconds'] = (now - last_activity).to_i if last_activity
    evidence
  end

  def nudges_after(turn)
    conversation.messages.where(private: false, message_type: :outgoing).where('created_at > ?', turn&.created_at || now)
                .select { |message| message.content_attributes['captain_followup'] == 'nudge' }
  end

  def reason(code, **values)
    I18n.t("captain.decisions.#{code}", locale: conversation.account.locale, **values)
  end

  def record(anchor, kind, suffix, outcome: 'completed', &)
    Captain::Decisions::Recorder.record(
      conversation: conversation, assistant: assistant, anchor_message: anchor,
      decision_key: "#{kind}:#{conversation.id}:#{suffix}", kind: kind, outcome: outcome,
      origin: 'time', trigger: 'inactivity', occurred_at: now, &
    )
  end
end
