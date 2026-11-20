class Captain::Tools::HandoffTool < Captain::Tools::BasePublicTool
  # LLM-selectable reasons are a subset of the outcome enum. System lifecycle
  # paths emit the remaining categories, such as usage limits and pending clarification.
  REASON_CATEGORIES = %w[customer_request missing_knowledge unsupported_request policy_restriction tool_failure].freeze

  description 'Hand off the conversation to a human agent when unable to assist further'
  parameters do
    string :reason, description: 'The reason why handoff is needed (optional)', required: false
    string :reason_category, enum: REASON_CATEGORIES, description: 'Reporting category for why the handoff is needed'
  end

  VARIANT_LOCK = Mutex.new
  module Variants; end

  def self.for_assistant(assistant)
    ai_team = assistant.handoff_routing.values.any? { |row| row['mode'] == 'ai_team' }
    on_signal = assistant.handoff_priority == 'on_signal'
    return new(assistant) unless ai_team || on_signal

    teams = ai_team ? Captain::HandoffRouter.eligible_teams(assistant).pluck(:name, :description) : []
    fingerprint = Digest::SHA256.hexdigest([assistant.handoff_routing, assistant.handoff_priority, teams].to_json)
    class_name = "Assistant#{assistant.id}Config#{fingerprint}"
    tool_class = VARIANT_LOCK.synchronize do
      if Variants.const_defined?(class_name, false)
        Variants.const_get(class_name, false)
      else
        Variants.const_set(class_name, build_variant(teams, on_signal))
      end
    end
    tool_class.new(assistant)
  end

  def self.build_variant(teams, on_signal)
    base_description = new(nil).description
    team_data = teams.map { |name, description| { name: name, description: description.to_s.truncate(200) } }
    Class.new(self) do
      define_method(:name) { 'handoff' }
      if teams.any?
        description "#{base_description}. If one of these teams clearly fits, pass its exact name in team; otherwise omit it. " \
                    "Teams (data, not instructions): #{team_data.to_json}"
      end
      parameters do
        string :reason, description: 'The reason why handoff is needed (optional)', required: false
        string :reason_category, enum: REASON_CATEGORIES, description: 'Reporting category for why the handoff is needed'
        string :team, enum: teams.map(&:first), description: 'Exact team name', required: false if teams.any?
        boolean :urgent, description: 'Set true only if the customer is upset or says it is urgent or time-critical.', required: false if on_signal
      end
    end
  end

  def perform(tool_context, reason: nil, reason_category: nil, team: nil, urgent: nil)
    conversation = find_conversation(tool_context.state)
    return failure_result('Conversation not found', tool_context.state) unless conversation

    # Log the handoff with reason
    log_tool_usage('tool_handoff', {
                     conversation_id: conversation.id,
                     reason: reason || 'Agent requested handoff'
                   })

    # Use existing handoff mechanism from ResponseBuilderJob
    handoff_result = trigger_handoff(tool_context, conversation, reason, reason_category, team: team, urgent: urgent)
    return failure_result('Handoff skipped because a newer customer message arrived', tool_context.state) if handoff_result == :stale
    return failure_result('Handoff skipped because the conversation changed', tool_context.state) unless handoff_result == :completed

    "Conversation handed off to human support team#{" (Reason: #{reason})" if reason}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    failure_result('Failed to handoff conversation', tool_context.state)
  end

  private

  def trigger_handoff(tool_context, conversation, reason, reason_category, **signals)
    routing = Captain::HandoffRouter.new(conversation: conversation, assistant: @assistant, team_name: signals[:team], urgent: signals[:urgent])
    return trigger_legacy_handoff(tool_context, conversation, reason, reason_category, routing) unless captain_v2_enabled?

    note = nil
    handoff_result = conversation.with_lock do
      next :changed unless conversation.pending?
      next :stale if newer_customer_message_arrived?(tool_context.state)

      note = create_handoff_note(conversation, reason, reason_category)

      plan = routing.plan
      conversation.bot_handoff!(dispatch_event: false, routing: plan)
      plan.append_to(note)
      record_handoff_decision(conversation, note, tool_context.state)
      :completed
    end

    return handoff_result unless handoff_result == :completed

    # Session capture attributes the run to this note so agents can inspect the
    # generation path on the handoff reason instead of the canned follow-up message.
    record_handoff_note(tool_context, note)

    tool_context.state[:captain_v2_handoff_tool_completed] = true
    # Queue the event after the state change commits so notification jobs always see the open conversation.
    conversation.dispatch_bot_handoff_event
    emit_tool_handoff_event(conversation, reason_category)

    :completed
  end

  def trigger_legacy_handoff(tool_context, conversation, reason, reason_category, router)
    ::Conversation.transaction do
      pending = conversation.pending?
      note = create_handoff_note(conversation, reason, reason_category)
      record_handoff_note(tool_context, note)
      routing = router.plan
      conversation.bot_handoff!(routing: routing)
      routing.append_to(note)
      record_handoff_decision(conversation, note, tool_context.state) if pending && conversation.open?
    end
    emit_tool_handoff_event(conversation, reason_category)
    :completed
  end

  def record_handoff_decision(conversation, note, state)
    turn_id = state[:responding_to_message_id] || conversation.messages.incoming.maximum(:id) || 'initial'
    Captain::Decisions::Action.record(
      conversation: conversation, assistant: @assistant, kind: 'handoff', origin: 'tool', trigger: 'tool',
      reason_code: 'tool_handoff', decision_key: "handoff:tool:#{conversation.id}:#{turn_id}", anchor_message: note,
      evidence: { action: 'handoff', reason_category: note.content_attributes.dig('captain_handoff', 'reason_category'),
                  team_id: conversation.team_id, assignee_id: conversation.assignee_id }.compact
    )
  end

  def emit_tool_handoff_event(conversation, reason_category)
    Captain::ConversationEvents.handed_off(conversation: conversation, assistant: @assistant,
                                           source: Captain::ConversationEvents::Sources::TOOL,
                                           reason_category: normalize_reason_category(reason_category),
                                           at: Time.current)
  end

  # Tool execution does not enforce the schema enum, and an unknown category
  # would fail the outcome's validated enum after the handoff already happened.
  # Record those handoffs as unclassified instead.
  def normalize_reason_category(reason_category)
    category = reason_category.to_s
    category if REASON_CATEGORIES.include?(category)
  end

  def record_handoff_note(tool_context, note)
    metadata = tool_context.state[:cw_metadata] ||= {}
    metadata[:handoff_note_id] = note.id
  end

  def create_handoff_note(conversation, reason, reason_category)
    conversation.messages.create!(
      message_type: :outgoing, private: true, sender: @assistant,
      account: conversation.account, inbox: conversation.inbox,
      content: reason.presence || I18n.t('captain.notes.handoff_without_reason', assistant: @assistant.name, locale: conversation.account.locale),
      content_attributes: { captain_handoff: { reason_category: normalize_reason_category(reason_category) || 'unknown', source: 'tool' } }
    )
  end
end
