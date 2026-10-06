module Whatsapp::Flows::ResponseToken
  PURPOSE = 'whatsapp_flow_response'.freeze

  module_function

  def generate(message)
    verifier.generate(message.id, purpose: PURPOSE)
  end

  def resolve(token, incoming)
    id = verifier.verified(token, purpose: PURPOSE) if token.is_a?(String)
    return unless id

    outgoing = incoming.account.messages.find_by(id: id)
    return unless outgoing&.outgoing? && outgoing.additional_attributes['whatsapp_flow']
    return unless outgoing.inbox_id == incoming.inbox_id
    return unless outgoing.conversation.contact_inbox_id == incoming.conversation.contact_inbox_id

    outgoing
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
