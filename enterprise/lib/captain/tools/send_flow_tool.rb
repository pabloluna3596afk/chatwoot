class Captain::Tools::SendFlowTool < Captain::Tools::BaseMessagingTool
  description 'Send the customer a form (WhatsApp Flow) to fill in, instead of asking for the data one message at a time. ' \
              'Use only a flow_id from list_available_flows and only when its purpose fits what the customer needs. It does not ' \
              'send right away: the form goes out as your reply to this message, so do not write the form yourself and never ' \
              'promise it unless this tool says it is prepared. If it says it is not possible, ask for the data in the chat.'
  param :flow_id, type: 'integer', desc: 'The flow_id of the form, from list_available_flows'
  param :intro_text, type: 'string', required: false,
                     desc: 'One short sentence shown with the form, up to 1024 characters (optional; the owner has a default)'
  param :customer_asked_again, type: 'boolean', required: false,
                               desc: 'true only if the customer explicitly asked to get the pending form again'

  def perform(tool_context, flow_id:, intro_text: nil, customer_asked_again: false)
    conversation, error = conversation_for(tool_context)
    return error if error

    id = integer_param(flow_id)
    return translate('errors.invalid_params') unless id

    request = Captain::Messaging::Request.new(kind: 'flow', resource: id, intro_text: intro_text.presence,
                                              resend_requested: customer_asked_again == true)
    prepare(conversation, tool_context, request)
  end
end
