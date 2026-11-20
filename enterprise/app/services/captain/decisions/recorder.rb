class Captain::Decisions::Recorder
  def self.record(conversation:, assistant:, decision_key:, **attributes)
    capture(conversation) do
      existing = Captain::Decision.find_by(account_id: conversation.account_id, decision_key: decision_key)
      next existing if existing

      attributes = attributes.merge(yield) if block_given?
      Captain::Decision.create_or_find_by!(account_id: conversation.account_id, decision_key: decision_key) do |decision|
        decision.assign_attributes(
          conversation: conversation, assistant: assistant, occurred_at: Time.current,
          reason_locale: conversation.account.locale, **attributes
        )
      end
    end
  end

  # Isolate PostgreSQL errors in a savepoint. Successful writes still roll back with the action.
  # Also use this boundary for optional session/activity attachment. Never log payloads or error messages.
  def self.capture(conversation, &)
    Captain::Decision.transaction(requires_new: true, &)
  rescue StandardError => e
    Rails.logger.error(
      "[Captain::Decisions::Recorder] account_id=#{conversation.account_id} conversation_id=#{conversation.id} error=#{e.class.name}"
    )
    nil
  end
end
