class Captain::Tools::TemplateCatalogTool < Captain::Tools::BaseMessagingTool
  CONTENT_LIMIT = 1000

  description 'List the message templates you may send in this conversation, with their content, variables and optional owner notes. ' \
              'Infer the purpose from the content; an existing owner note takes priority. A template is a paid ' \
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
    eligible = availability.templates.select { |item| %w[available needs_data].include?(item.state) }
    items = eligible.sort_by { |item| [item.note.present? ? 0 : 1, item.resource['name']] }
    items.filter_map { |item| template_payload(conversation, item) }
  end

  def template_payload(conversation, item)
    entry = matching_template(conversation, item)
    return unless entry

    entry = entry.merge('processed_params' => item.processed_params)
    reason = reason_for(conversation, entry)
    { name: item.resource['name'], language: item.resource['language'], category: item.resource['category'],
      text: component_text(entry, 'BODY'), header: component_text(entry, 'HEADER'), footer: component_text(entry, 'FOOTER'),
      buttons: button_labels(entry), variables: Captain::TemplateMessage.variables(entry).map(&:to_h),
      truncated: truncated?(entry), purpose: item.note.presence, can_send: reason.nil?, reason: reason }.compact
  end

  def matching_template(conversation, item)
    Array(conversation.inbox.channel.message_templates).find do |candidate|
      candidate['name'] == item.resource['name'] && candidate['language'].to_s.casecmp?(item.resource['language'])
    end
  end

  def component_text(entry, type)
    text = Array(entry['components']).find { |component| component['type'].to_s.casecmp?(type) }&.dig('text').to_s
    text.truncate(CONTENT_LIMIT)
  end

  def truncated?(entry)
    Array(entry['components']).any? { |component| component['text'].to_s.length > CONTENT_LIMIT }
  end

  def button_labels(entry)
    buttons = Array(entry['components']).select { |component| component['type'].to_s.casecmp?('BUTTONS') }
    buttons.flat_map { |component| Array(component['buttons']).filter_map { |button| button['text'] } }
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
