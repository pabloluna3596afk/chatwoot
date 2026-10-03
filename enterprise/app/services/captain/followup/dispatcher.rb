# Runs every minute (Conversations::CaptainFollowupJob). For every inbox whose assistant has follow-up on:
# - inactivity: nudges and closes the pending conversations Captain is handling (Captain::Followup::Nudger);
# - re-engagement: sends one template to the conversations Captain closed for inactivity (Captain::Followup::Reengager).
class Captain::Followup::Dispatcher
  BATCH_SIZE = 100

  def initialize(now: Time.current)
    @now = now
  end

  def perform
    CaptainInbox.includes(:inbox, :captain_assistant).find_each(batch_size: 100) do |captain_inbox|
      assistant = captain_inbox.captain_assistant
      inbox = captain_inbox.inbox
      next if assistant.blank? || inbox.blank? || inbox.email? || inbox.external_bot_active?

      nudge_inactive(assistant, inbox)
      reengage(assistant, inbox)
    end
  end

  private

  attr_reader :now

  def nudge_inactive(assistant, inbox)
    settings = assistant.followup
    return unless settings.inactivity_enabled? && settings.max_nudges.positive?

    cutoff = now - [settings.inactivity_after_minutes, settings.close_after_minutes].min.minutes
    inbox.conversations.attended_by_ai.where(assignee_agent_bot_id: assistant.id).where(last_activity_at: ..cutoff)
         .order(:last_activity_at).limit(BATCH_SIZE).each do |conversation|
      run { Captain::Followup::Nudger.new(conversation, assistant, now: now).perform }
    end
  end

  def reengage(assistant, inbox)
    return unless assistant.followup.reengagement_enabled?

    Captain::Followup::Reengager.candidates(inbox, now: now).limit(BATCH_SIZE).each do |conversation|
      run { Captain::Followup::Reengager.new(conversation, assistant, now: now).perform }
    end
  end

  # One conversation failing never stops the others.
  def run
    yield
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
  ensure
    Current.reset
  end
end
