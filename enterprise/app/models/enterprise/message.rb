module Enterprise::Message
  COMPLETION_CANCEL_CAUSES = { 'incoming' => 'new_incoming', 'outgoing' => 'human_reply' }.freeze

  def self.prepended(base)
    base.class_eval do
      after_create :cancel_captain_completion_signal
      has_many :captain_decisions, class_name: 'Captain::Decision', foreign_key: :anchor_message_id, dependent: :nullify, inverse_of: :anchor_message

      has_one :call, class_name: 'Call', foreign_key: :message_id, dependent: :nullify, inverse_of: :message

      scope :with_call, -> { includes(call: [:contact, { inbox: :channel }]) }
      # Scheduling and freshness checks must share this scope so an email auto reply cannot cancel a pending response.
      scope :captain_response_triggering, lambda {
        incoming.joins(:inbox).where(
          "((messages.content_attributes #>> '{}')::jsonb -> 'email' ->> 'auto_reply') IS DISTINCT FROM 'true' OR " \
          "(messages.content_type != :incoming_email AND inboxes.channel_type != 'Channel::Email')",
          incoming_email: content_types[:incoming_email]
        )
      }
    end
  end

  def push_event_data
    data = super
    data[:call] = call.push_event_data if content_type == 'voice_call' && call.present?
    data
  end

  def captain_response_triggering?
    return incoming? && !auto_reply_email? unless persisted?

    self.class.captain_response_triggering.exists?(id: id)
  end

  private

  def cancel_captain_completion_signal
    return unless incoming? || (outgoing? && !private? && sender_type == 'User')
    return unless conversation.additional_attributes.keys.intersect?(%w[captain_completion captain_loop_guard])

    conversation.with_lock do
      cause = COMPLETION_CANCEL_CAUSES.fetch(message_type)
      ::Captain::Conversation::CompletionSignal.cancel(conversation, cause: cause)
      conversation.save! if conversation.changed?
    end
  end

  def reopen_resolved_conversation
    assistant = conversation.inbox.captain_assistant

    return super if assistant.blank? || conversation.inbox.external_bot_active?

    result = assistant.engagement_result(conversation.contact, conversation)
    unless result[:engages]
      conversation.record_captain_skip(assistant, result)
      return conversation.open!
    end

    super
    own_reopened_conversation(assistant)
  end

  # A resolved conversation that the customer reopens for Captain is handed to the assistant: any person who was
  # assigned is cleared and the assistant becomes the owner, as in a brand new conversation. If a person replies
  # afterwards they take it back (see #mark_pending_conversation_as_open_for_human_response). Nothing changes when
  # the assistant already owns it. The team is left untouched.
  def own_reopened_conversation(assistant)
    return unless conversation.pending?
    return if conversation.ai_assignee == assistant && conversation.assignee_id.blank?

    attributes = conversation.additional_attributes.merge('captain_reopened_at' => Time.current.iso8601)
    attributes['captain_previous_assignee_id'] = conversation.assignee_id if conversation.assignee_id
    conversation.update!(assignee_id: nil, ai_assignee: assistant, additional_attributes: attributes)
  end

  def mark_pending_conversation_as_open_for_human_response
    return unless captain_pending_conversation? || captain_escalated_conversation?
    return unless human_response?
    return if bot_response?
    return if private?
    return if template_bootstrap_message?

    author = sender
    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = nil

    begin
      # An agent's reply takes the conversation: Captain's ownership is cleared and the agent becomes the assignee,
      # which also clears the escalation mark.
      conversation.ai_assignee = nil if conversation.ai_assignee_type == 'Captain::Assistant'
      conversation.assignee = author if author.is_a?(User) && conversation.assignee_id.blank?
      conversation.open!
      return unless conversation.saved_change_to_status?

      create_captain_auto_open_activity_message
    ensure
      Current.user = previous_user
      Current.executed_by = previous_executed_by
    end
  end

  def captain_pending_conversation?
    return false unless conversation.pending?

    ::CaptainInbox.exists?(inbox_id: conversation.inbox_id)
  end

  def captain_escalated_conversation?
    conversation.captain_escalated?
  end

  def template_bootstrap_message?
    additional_attributes['template_params'].present? &&
      !conversation.messages.incoming.exists?
  end

  def create_captain_auto_open_activity_message
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale)
    )
  end
end
