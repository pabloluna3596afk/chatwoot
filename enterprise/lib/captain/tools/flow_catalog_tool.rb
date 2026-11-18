class Captain::Tools::FlowCatalogTool < Captain::Tools::BaseMessagingTool
  CONTENT_LIMIT = 1000

  description 'List the forms (WhatsApp Flows) you may send in this conversation, with first-screen content, optional owner notes and the fields ' \
              'it asks. Infer the purpose from the content; an existing owner note takes priority. ' \
              'Call it before send_flow; only these forms can be sent.'

  def perform(tool_context)
    conversation, error = conversation_for(tool_context)
    return error if error

    { window_open: conversation.can_reply?, flows: flows(conversation) }.to_json
  end

  private

  def flows(conversation)
    availability = Captain::Messaging::Availability.new(@assistant, conversation.inbox)
    flows = availability.eligible_flows.index_by(&:id)
    availability.flows.select(&:available?).map do |item|
      flow = flows[item.resource['id']]
      { flow_id: flow.id, name: flow.name, purpose: item.note.presence, first_screen: first_screen(flow), fields: fields(flow),
        can_send: conversation.can_reply?, reason: reason(flow, conversation) }.compact
    end
  rescue Whatsapp::Flows::SendFlowService::Error
    []
  end

  def first_screen(flow)
    screen = flow.definition.fetch('screens').first
    texts = Array(screen['blocks']).filter_map do |block|
      block['text'] if Whatsapp::Flows::Spec::TEXT_BLOCKS.include?(block['type'])
    end
    text = texts.join("\n")
    { title: screen['title'], text: text.truncate(CONTENT_LIMIT), button: screen['button'], truncated: text.length > CONTENT_LIMIT }
  end

  def fields(flow)
    Whatsapp::Flows::Spec.fields(flow.definition).pluck(:definition).map { |field| field.slice('label', 'type') }
  end

  def reason(flow, conversation)
    return translate('errors.unavailable') unless flow

    translate('errors.window_closed') unless conversation.can_reply?
  end
end
