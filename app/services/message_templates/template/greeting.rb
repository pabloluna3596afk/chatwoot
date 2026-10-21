class MessageTemplates::Template::Greeting
  pattr_initialize [:conversation!]

  def perform
    ActiveRecord::Base.transaction do
      message = conversation.messages.build(greeting_message_params)
      message.variables_resolved!
      message.save!
    end
  rescue Variables::DeliveryRenderer::Error => e
    Variables::Omission.create_note(conversation: conversation, surface: 'greeting', error: e)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    true
  end

  private

  delegate :contact, :account, to: :conversation
  delegate :inbox, to: :message

  def greeting_message_params
    drops = Variables::ContextFactory.new(account: account, records: { conversation: conversation }).build(surface: 'message')
    content = Variables::DeliveryRenderer.new(drops: drops).render(conversation.inbox.greeting_message, protect_code: true)

    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :template,
      content: content
    }
  end
end
