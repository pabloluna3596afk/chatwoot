class Captain::Tools::TemplateCatalogTool < Captain::Tools::BaseMessagingTool
  description 'List the message templates you may send in this conversation, with what each one is for. A template is a paid ' \
              'WhatsApp message: use it only when the customer needs exactly that and a normal reply or a form does not do. ' \
              'Call it before send_template; only these templates can be sent.'

  def perform(tool_context)
    conversation, error = conversation_for(tool_context)
    return error if error

    { templates: templates(conversation) }.to_json
  end

  private

  def templates(conversation)
    Array(@assistant.messaging.entry_for(conversation.inbox_id)&.dig('templates')).map do |entry|
      reason = reason_for(conversation, entry)
      { name: entry['name'], language: entry['language'], purpose: purpose_of(entry), can_send: reason.nil?, reason: reason }.compact
    end
  end

  def reason_for(conversation, entry)
    approved = Captain::TemplateMessage.approved(conversation.inbox, entry)
    return translate('errors.unavailable') unless approved
    return translate('errors.paid_off') unless @assistant.allow_paid_templates?

    Captain::TemplateMessage.build(approved, entry['processed_params'], Captain::TemplateMessage.drops(conversation, @assistant))
    nil
  rescue Captain::TemplateMessage::MappingMismatch
    translate('errors.missing_variables')
  end
end
