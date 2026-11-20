class Captain::Decisions::SessionSummary
  def self.build(session)
    # Read only tool identifiers. Never expose contents, arguments, results, thinking or prompts.
    { actions: actions(session.run_context) }
  end

  def self.current_turn_actions(context)
    history = Array(context[:conversation_history])
    turn_start = context[:captain_v2_turn_start_index] || history.rindex { |entry| entry[:role].to_s == 'user' } || 0
    actions(history[turn_start..])
  end

  def self.actions(history)
    actions = Array(history).flat_map do |entry|
      next [] unless entry.is_a?(Hash)

      entry = entry.with_indifferent_access
      next [] unless entry['role'].to_s == 'assistant'

      Array(entry['tool_calls']).filter_map do |call|
        next unless call.is_a?(Hash)

        name = call.with_indifferent_access['name'].to_s.split('--').last.to_s
        { type: 'tool', name: name } if name.match?(/\A[a-z][a-z0-9_]{0,79}\z/)
      end
    end
    actions.uniq.first(50)
  end
end
