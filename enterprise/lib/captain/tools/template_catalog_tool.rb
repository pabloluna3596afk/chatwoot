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
    availability = Captain::Messaging::Availability.new(@assistant, conversation.inbox)
    availability.templates.select(&:available?).sort_by { |item| [item.note.present? ? 0 : 1, item.resource['name']] }.first(20).filter_map do |item|
      entry = Array(conversation.inbox.channel.message_templates).find do |candidate|
        candidate['name'] == item.resource['name'] && candidate['language'].to_s.casecmp?(item.resource['language'])
      end
      next unless entry

      entry = entry.merge('processed_params' => item.processed_params) if @assistant.messaging.mode(conversation.inbox_id) == 'auto'
      reason = reason_for(conversation, entry)
      body = Array(entry['components']).find { |component| component['type'].to_s.casecmp?('BODY') }&.dig('text')
      buttons = Array(entry['components']).select { |component| component['type'].to_s.casecmp?('BUTTONS') }
                                          .flat_map { |component| Array(component['buttons']).filter_map { |button| button['text'] } }
      { name: item.resource['name'], language: item.resource['language'], category: item.resource['category'],
        text: body.to_s, buttons: buttons, purpose: item.note, can_send: reason.nil?, reason: reason }.compact
    end
  end

  def reason_for(conversation, entry)
    approved = Captain::TemplateMessage.approved(conversation.inbox, entry)
    return translate('errors.unavailable') unless approved
    return translate('errors.paid_off') unless @assistant.allow_paid_templates?

    Captain::TemplateMessage.build(approved, entry['processed_params'], Captain::TemplateMessage.drops(conversation, @assistant))
    nil
  rescue Captain::TemplateMessage::MappingMismatch, Variables::DeliveryRenderer::Error
    translate('errors.missing_variables')
  end
end
