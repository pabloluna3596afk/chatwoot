module Enterprise::Conversations::AssignmentService
  def perform
    return super unless assignee_type.to_s == 'Captain::Assistant'
    return unless conversation.account.feature_enabled?('captain_integration')

    assign_ai_assignee(captain_assistant)
  end

  def assign_ai_assignee(ai_assignee)
    return unless ai_assignee

    responding_to_message = conversation.with_lock { assign_captain_under_lock(ai_assignee) }

    Captain::Conversation::ResponseSchedulerService.new(message: responding_to_message).perform if responding_to_message
    ai_assignee
  ensure
    conversation.assignment_driven_status = false
  end

  private

  def open_on_assignment?
    super || conversation.ai_assignee_type == 'Captain::Assistant'
  end

  def captain_assistant
    assistant = conversation.inbox.captain_assistant
    assistant if assistant&.id == assignee_id.to_i && !assistant.internal?
  end

  def latest_unanswered_customer_message(assignment_message_id)
    latest_message = conversation.messages.incoming.where(private: false).captain_response_triggering.order(id: :desc).first
    return unless latest_message && latest_message.id <= assignment_message_id
    return if conversation.messages.outgoing.where(private: false).exists?(['messages.id > ?', latest_message.id])

    latest_message
  end

  def assignment_response_allowed?(assistant)
    captain_assignment_current?(assistant) && captain_inbox_available? &&
      assistant.responds_to_audience?(conversation.contact, conversation) && whatsapp_reply_window_open?
  end

  def assign_captain_under_lock(assistant)
    return if conversation.pending? && conversation.ai_assignee == assistant

    assignment_message_id = conversation.messages.maximum(:id) || 0
    conversation.assignee = nil
    conversation.ai_assignee = assistant
    conversation.status = :pending
    conversation.assignment_driven_status = conversation.captain_assigned?
    write_assignment_boundary(assignment_message_id)
    conversation.save!
    schedule_assignment_response(assistant, assignment_message_id)
  end

  def write_assignment_boundary(message_id)
    conversation.additional_attributes = conversation.additional_attributes.merge(
      'captain_assignment_message_id' => message_id,
      'captain_assignment_response_message_id' => nil
    )
  end

  def schedule_assignment_response(assistant, assignment_message_id)
    message = latest_unanswered_customer_message(assignment_message_id)
    return unless message && assignment_response_allowed?(assistant)

    conversation.update!(additional_attributes: conversation.additional_attributes.merge(
      'captain_assignment_response_message_id' => message.id
    ))
    message
  end

  def captain_assignment_current?(assistant)
    conversation.pending? && conversation.ai_assignee == assistant
  end

  def captain_inbox_available?
    conversation.inbox.captain_active? && !conversation.inbox.external_bot_active?
  end

  def whatsapp_reply_window_open?
    conversation.inbox.channel_type != 'Channel::Whatsapp' || conversation.can_reply?
  end
end
