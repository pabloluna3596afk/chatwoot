class Captain::Tools::ListAvailableFlowsTool < Captain::Tools::BaseMessagingTool
  description 'List the forms (WhatsApp Flows) you may send in this conversation, with what each one is for and the fields ' \
              'it asks. Call it before send_flow; only these forms can be sent.'

  def perform(tool_context)
    conversation, error = conversation_for(tool_context)
    return error if error

    { window_open: conversation.can_reply?, flows: flows(conversation) }.to_json
  end

  private

  def flows(conversation)
    published = Whatsapp::Flows::SendFlowService.new(conversation: conversation, sender: @assistant).eligible_flows.index_by(&:id)
    Array(@assistant.messaging.entry_for(conversation.inbox_id)&.dig('flows')).map do |entry|
      flow = published[entry['flow_id']]
      { flow_id: entry['flow_id'], name: flow&.name, purpose: purpose_of(entry), fields: flow ? fields(flow) : [],
        can_send: flow.present? && conversation.can_reply?, reason: reason(flow, conversation) }.compact
    end
  rescue Whatsapp::Flows::SendFlowService::Error
    []
  end

  def fields(flow)
    Whatsapp::Flows::Spec.fields(flow.definition).pluck(:definition).map { |field| field.slice('label', 'type') }
  end

  def reason(flow, conversation)
    return translate('errors.unavailable') unless flow

    translate('errors.window_closed') unless conversation.can_reply?
  end
end
