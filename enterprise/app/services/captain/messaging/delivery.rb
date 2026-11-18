class Captain::Messaging::Delivery
  def initialize(conversation:, assistant:, request:, audit:)
    @conversation = conversation
    @assistant = assistant
    @request = request
    @audit = audit
  end

  def send_flow
    params = { 'whatsapp_flow_id' => @request.resource }
    params['body'] = @request.intro_text if @request.intro_text.present?
    message = Whatsapp::Flows::SendFlowService.new(conversation: @conversation, sender: @assistant, params: params).perform
    message.update!(additional_attributes: message.additional_attributes.merge(Captain::Messaging::Limits::KEY => @audit))
    message
  end

  def send_template(payload, text)
    factory.create(text, additional_attributes: { 'template_params' => payload,
                                                  Captain::Messaging::Limits::KEY => @audit })
  end

  def note(name, kind)
    content = I18n.t("captain.messaging.note_#{kind}", locale: @conversation.account.locale, name: name)
    factory.create(content, private: true, preserve_waiting_since: true)
  end

  private

  def factory
    @factory ||= Captain::Messaging::MessageFactory.new(@conversation, @assistant)
  end
end
