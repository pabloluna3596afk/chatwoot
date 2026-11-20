module Captain::Conversation::DecisionRecording
  private

  def create_recorded_handoff_note(routing, source, reason_category, note_key)
    note = @conversation.messages.create!(
      message_type: :outgoing, private: true, sender: @assistant, account: account, inbox: inbox,
      content: [I18n.t("captain.notes.#{note_key}", assistant: @assistant.name), routing.note].compact.join("\n"),
      content_attributes: { captain_handoff: { reason_category: reason_category, source: source } }
    )
    record_legacy_handoff_decision(note, source)
  end

  def record_legacy_handoff_decision(note, source)
    trigger = { 'reply_limit' => 'reply_limit', 'generation_failure' => 'error' }.fetch(source, 'tool')
    Captain::Decisions::Recorder.record(
      conversation: @conversation, assistant: @assistant, decision_key: "handoff:#{@conversation.id}:#{job_id}",
      anchor_message: note, kind: 'handoff', outcome: 'completed', origin: trigger == 'tool' ? 'model' : 'rule',
      trigger: trigger, reason_code: "#{trigger}_handoff", reason_text: note.content.first(Captain::Decision::REASON_TEXT_LIMIT)
    ) do
      { settings_snapshot: trigger == 'reply_limit' ? { 'max_replies_per_conversation' => @assistant.max_replies } : {} }
    end
  end

  def record_reply_decision(message)
    @reply_decision = Captain::Decisions::Recorder.record(
      conversation: @conversation, assistant: @assistant, decision_key: "reply:#{@conversation.id}:#{job_id}",
      anchor_message: message, kind: 'reply', outcome: 'created', origin: 'model', trigger: 'customer_message',
      reason_code: 'model_reply'
    ) do
      { reason_text: @response['reasoning']&.first(Captain::Decision::REASON_TEXT_LIMIT), evidence: reply_evidence(message),
        technical_details: reply_technical_details }
    end
  end

  def reply_evidence(message)
    metadata = @run_result&.context&.dig(:state, :cw_metadata) || {}
    evidence = metadata.slice(:document_ids, :faq_ids, :used_faq_ids).stringify_keys
    context = @run_result&.context || {}
    evidence['tools'] = Captain::Decisions::SessionSummary.current_turn_actions(context).pluck(:name)
    evidence['cited_document_ids'] = Captain::Assistant::CitationDocumentIds.call(assistant: @assistant, message: message, context: context)
    evidence['evaluated_through_message_id'] = @responding_to_message_id if @responding_to_message_id
    evidence
  end

  def reply_technical_details
    details = {}
    units = AiUsageReservation.joins(:account_plan_usage).where(account_plan_usages: { account_id: account.id })
                              .where(reservation_id: @reply_reservation_id, bucket: 'captain_responses', released_at: nil).pick(:units)
    details[:credits_consumed] = units if units
    details[:model] = @assistant.agent_model if captain_v2_enabled?
    details
  end

  def attach_decision_session(session)
    return unless session && @reply_decision

    Captain::Decisions::Recorder.capture(@conversation) do
      @reply_decision.update!(agent_session: session, evidence: @reply_decision.evidence.merge('cited_document_ids' => session.cited_document_ids))
    end
  end
end
