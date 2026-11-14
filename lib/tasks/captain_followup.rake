namespace :captain do
  namespace :followup do
    desc 'Preview stale unanswered Captain conversations; set DRY_RUN=false to close them'
    task close_stale: :environment do
      dry_run = ENV.fetch('DRY_RUN', 'true') != 'false'
      now = Time.current
      cutoff = now - Captain::Followup::Dispatcher::MAX_AGE
      CaptainInbox.includes(:inbox, :captain_assistant).find_each do |link|
        assistant = link.captain_assistant
        next unless Captain::Pilot.enabled?(link.inbox.account) && assistant.evaluate_inactive_conversations_before_resolving?

        link.inbox.conversations.attended_by_ai.where(assignee_agent_bot_id: assistant.id)
            .where('last_activity_at < ?', cutoff).find_each do |conversation|
          result = conversation.with_lock do
            conversation.reload
            next unless conversation.captain_attended? && conversation.ai_assignee == assistant
            next unless conversation.last_activity_at < cutoff && Captain::Conversation::Turn.awaiting_customer?(conversation, assistant)
            next :preview if dry_run

            Captain::Followup::Closer.new(conversation, assistant, now: now, note_key: 'captain.notes.closed_unanswered',
                                                                   send_resolution_message: false).perform
          end
          puts "#{dry_run ? 'Would close' : 'Closed'} conversation_id=#{conversation.id} assistant_id=#{assistant.id}" if result
          if result == :closed
            Captain::ConversationEvents.resolved(conversation: conversation, assistant: assistant,
                                                 source: Captain::ConversationEvents::Sources::TIME_BASED, at: now)
          end
        ensure
          Current.reset
        end
      end
    end
  end
end
