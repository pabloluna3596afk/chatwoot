class Captain::ReviewCompletionSignalsJob < ApplicationJob
  queue_as :low

  def perform
    Conversation.attended_by_ai
                .where("additional_attributes -> 'captain_completion' ->> 'status' IN (?)", Captain::Conversation::CompletionSignal::ACTIVE_STATUSES)
                .where("additional_attributes -> 'captain_completion' ->> 'due_at' <= ?", Time.current.utc.iso8601)
                .limit(Limits::BULK_ACTIONS_LIMIT).each do |conversation|
      Captain::Conversation::CompletionSignal.new(conversation, conversation.ai_assignee).review
    end
  end
end
