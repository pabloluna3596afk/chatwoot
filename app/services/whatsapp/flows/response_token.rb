module Whatsapp::Flows::ResponseToken
  PURPOSE = 'whatsapp_flow_response'.freeze

  module_function

  def generate(message)
    verifier.generate(message.id, purpose: PURPOSE)
  end

  def resolve(token, incoming)
    id = verified_id(token)
    return unless id

    outgoing = incoming.account.messages.find_by(id: id)
    return unless flow_message?(outgoing)
    return unless same_identity?(outgoing, incoming)

    outgoing
  end

  def verified_id(token)
    verifier.verified(token, purpose: PURPOSE) if token.is_a?(String)
  end

  def flow_message?(message)
    message&.outgoing? && message.additional_attributes['whatsapp_flow']
  end

  def same_identity?(outgoing, incoming)
    outgoing.inbox_id == incoming.inbox_id &&
      outgoing.conversation.contact_inbox_id == incoming.conversation.contact_inbox_id
  end

  private_class_method :verified_id, :flow_message?, :same_identity?

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
