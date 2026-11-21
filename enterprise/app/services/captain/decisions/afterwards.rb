# Retained structured facts only, ending at the next customer turn. Never infer history from today's status.
class Captain::Decisions::Afterwards
  MAX_FACTS = 2
  ATTRIBUTES_SQL = "(content_attributes #>> '{}')::jsonb".freeze
  EVENT_SQL = <<~SQL.squish.freeze
    (message_type = :incoming AND private = false) OR #{ATTRIBUTES_SQL} ? 'captain_handoff' OR
    (message_type = :activity AND #{ATTRIBUTES_SQL} -> 'activity' ->> 'type' = 'conversation_status_changed' AND
     (#{ATTRIBUTES_SQL} -> 'activity' ->> 'status' = 'resolved' OR
      (#{ATTRIBUTES_SQL} -> 'activity' ->> 'status' = 'open' AND
       #{ATTRIBUTES_SQL} -> 'activity' ->> 'previous_status' = 'resolved')))
  SQL

  def self.build(decision)
    controls = retained_controls(decision)
    events = controls.map { |control| control_event(control) } + message_events(decision, controls)
    facts = []
    events.sort_by { |event| [event[:occurred_at], event[:priority], event[:id]] }.each do |event|
      facts << event.slice(:type, :occurred_at)
      break if event[:type] == 'new_incoming' || facts.size == MAX_FACTS
    end
    { status: facts.empty? ? 'not_recorded' : 'recorded', facts: facts }
  end

  def self.retained_controls(decision)
    decision.conversation.captain_decisions.where(kind: %w[reopen human_control disengage])
            .where('occurred_at > ?', decision.occurred_at).includes(:anchor_message).order(:occurred_at, :id).limit(MAX_FACTS)
  end

  def self.control_event(control)
    at = control.kind == 'reopen' ? control.anchor_message&.created_at || control.occurred_at : control.occurred_at
    { type: control.kind == 'reopen' ? 'reopened' : control.kind, occurred_at: at, id: control.id, priority: 0 }
  end

  def self.message_events(decision, controls)
    messages = decision.conversation.messages.where('created_at > ?', decision.occurred_at)
                       .where(EVENT_SQL, incoming: Message.message_types[:incoming], activity: Message.message_types[:activity])
                       .where.not(id: decision.anchor_message_id).order(:created_at, :id).limit(MAX_FACTS + controls.size)
    messages.filter_map do |message|
      next if fact_type(message) == 'reopened' && controls.any? { |control| control.anchor_message_id == message.id }

      { type: fact_type(message), occurred_at: message.created_at, id: message.id, priority: 1 }
    end
  end

  def self.fact_type(message)
    return 'new_incoming' if message.incoming?
    return 'handoff' if message.content_attributes['captain_handoff'].present?

    message.content_attributes.dig('activity', 'status') == 'resolved' ? 'resolved' : 'reopened'
  end
end
