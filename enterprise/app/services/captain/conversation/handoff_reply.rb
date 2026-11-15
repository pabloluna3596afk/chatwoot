# What the customer hears when Captain hands the conversation over: the inbox's out-of-office
# message when it applies, otherwise the assistant's handoff message. Never both.
class Captain::Conversation::HandoffReply
  attr_reader :message

  def initialize(conversation, assistant, fallback: nil)
    @conversation = conversation
    @assistant = assistant
    @fallback = fallback
  end

  def perform
    started_at = Time.current
    inbox = @conversation.inbox
    if @conversation.campaign.blank? && inbox.out_of_office? && inbox.out_of_office_message.present?
      content = rendered_out_of_office_content(inbox.out_of_office_message)
      ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation)
      @message = @conversation.messages.template.where(content: content, created_at: started_at..).last
      return :out_of_office if @message
    end

    send_handoff_message
  end

  private

  # Message's Liquidable callback resolves variables before persistence, so compare the same rendered content.
  def rendered_out_of_office_content(content)
    template = Message.new(conversation: @conversation, message_type: :template, content: content,
                           account_id: @conversation.account_id, inbox_id: @conversation.inbox_id)
    Variables::Resolver.new(drops: Variables::ContextFactory.for_message(template)).render(content, protect_code: true)
  rescue Liquid::Error
    content
  end

  def send_handoff_message
    content = @assistant.config['handoff_message'].presence || @fallback
    return if content.blank?

    @message = @conversation.messages.create!(
      message_type: :outgoing, account_id: @conversation.account_id, inbox_id: @conversation.inbox_id,
      sender: @assistant, content: content, preserve_waiting_since: !@conversation.pending?
    )
    :handoff_message
  end
end
