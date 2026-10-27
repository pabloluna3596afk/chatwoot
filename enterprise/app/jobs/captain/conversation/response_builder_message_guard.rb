module Captain::Conversation::ResponseBuilderMessageGuard
  private

  def assignment_boundary_passes?
    assignment_message_id = @conversation.additional_attributes['captain_assignment_message_id']
    assignment_response_message_id = @conversation.additional_attributes['captain_assignment_response_message_id']
    return true unless assignment_message_id
    return true if assignment_response_message_id == @responding_to_message_id

    @conversation.messages.captain_response_triggering.exists?(['messages.id > ?', assignment_message_id])
  end

  def newer_customer_message_arrived?
    return false if @responding_to_message_id.blank?

    Conversation.uncached do
      @conversation.messages.captain_response_triggering.exists?(['messages.id > ?', @responding_to_message_id])
    end
  end
end
