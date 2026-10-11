# The Flow or template a Captain tool prepared for the reply being written. The model never sends anything: the tool
# stashes the request here for the conversation, and when the response job posts the reply it takes the request and
# hands it to Captain::Messaging::SendService, which checks everything again and sends the message instead of the
# model's text. One request per customer message; a request stashed for a different customer message (a run that was
# discarded) is dropped instead of leaking into a later reply.
class Captain::Messaging::Intent
  TTL = 10.minutes.to_i

  class << self
    # Keeps the request, or returns false when this customer message already has one.
    def stash(conversation, request)
      return false if pending?(conversation, request.responding_to_message_id)

      Redis::Alfred.setex(key(conversation), request.to_h.to_json, TTL)
      true
    end

    # The request for this customer message, or nil. It is cleared either way.
    def take(conversation, responding_to:)
      raw = Redis::Alfred.get(key(conversation))
      return if raw.blank?

      Redis::Alfred.delete(key(conversation))
      request_from(JSON.parse(raw), responding_to)
    end

    def pending?(conversation, responding_to)
      raw = Redis::Alfred.get(key(conversation))
      raw.present? && JSON.parse(raw)['responding_to_message_id'] == responding_to
    end

    private

    def request_from(data, responding_to)
      return unless data['responding_to_message_id'] == responding_to

      resource = data['resource']
      resource = resource.symbolize_keys if resource.is_a?(Hash)
      Captain::Messaging::Request.new(kind: data['kind'], resource: resource, responding_to_message_id: responding_to,
                                      intro_text: data['intro_text'], resend_requested: data['resend_requested'])
    end

    def key(conversation)
      format(Redis::RedisKeys::CAPTAIN_MESSAGING_INTENT, conversation_id: conversation.id)
    end
  end
end
