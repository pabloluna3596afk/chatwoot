# Retained structured facts only, ending at the next customer turn. Never infer history from today's status.
class Captain::Decisions::Afterwards
  ATTRIBUTES_SQL = "(content_attributes #>> '{}')::jsonb".freeze
  EVENT_SQL = <<~SQL.squish.freeze
    (message_type = :incoming AND private = false) OR #{ATTRIBUTES_SQL} ? 'captain_handoff' OR
    (message_type = :activity AND #{ATTRIBUTES_SQL} -> 'activity' ->> 'type' = 'conversation_status_changed' AND
     (#{ATTRIBUTES_SQL} -> 'activity' ->> 'status' = 'resolved' OR
      (#{ATTRIBUTES_SQL} -> 'activity' ->> 'status' = 'open' AND
       #{ATTRIBUTES_SQL} -> 'activity' ->> 'previous_status' = 'resolved')))
  SQL

  def self.build(decision)
    messages = decision.conversation.messages.where('created_at > ?', decision.occurred_at)
                       .where(EVENT_SQL, incoming: Message.message_types[:incoming], activity: Message.message_types[:activity])
                       .where.not(id: decision.anchor_message_id).order(:created_at, :id).limit(2)
    facts = []
    messages.each do |message|
      fact = fact_type(message)
      facts << { type: fact, occurred_at: message.created_at }
      break if fact == 'new_incoming'
    end
    { status: facts.empty? ? 'not_recorded' : 'recorded', facts: facts }
  end

  def self.fact_type(message)
    return 'new_incoming' if message.incoming?
    return 'handoff' if message.content_attributes['captain_handoff'].present?

    message.content_attributes.dig('activity', 'status') == 'resolved' ? 'resolved' : 'reopened'
  end
end
