class Captain::Messaging::MessageFactory
  def initialize(conversation, assistant)
    @conversation = conversation
    @assistant = assistant
    @account = conversation.account
    @inbox = conversation.inbox
  end

  def create(content, **attributes)
    message = @conversation.messages.build(message_type: :outgoing, account_id: @account.id, inbox_id: @inbox.id,
                                           sender: @assistant, content: content, **attributes)
    message.variables_resolved! if template_message?(attributes)
    message.save!
    message
  end

  private

  def template_message?(attributes)
    attributes[:additional_attributes]&.with_indifferent_access&.key?(:template_params)
  end
end
