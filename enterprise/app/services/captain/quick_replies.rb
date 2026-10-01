# Buttons ("input_select" items) that a Captain tool wants on the assistant's next reply.
#
# The model never writes the buttons: a tool stashes them here for the conversation, and when the
# response job posts the model's reply it takes them and sends one input_select message (the
# model's text is the question, the items are the buttons). WhatsApp turns up to 3 items into
# reply buttons and more into a list; the web widget renders them as buttons.
class Captain::QuickReplies
  TTL = 10.minutes.to_i
  MAX_ITEMS = 10
  INTERACTIVE_CHANNELS = %w[Channel::WebWidget Channel::Telegram Channel::FacebookPage Channel::Line].freeze

  class << self
    # Whether the inbox renders input_select as buttons. Others get numbered text from the tools.
    def supported?(inbox)
      return inbox.channel.provider == 'whatsapp_cloud' if inbox.channel_type == 'Channel::Whatsapp'

      INTERACTIVE_CHANNELS.include?(inbox.channel_type)
    end

    def item(title, value)
      { 'title' => title, 'value' => value }
    end

    # Replaces anything already waiting: only the buttons of the latest tool call are sent.
    def stash(conversation, items, responding_to: nil)
      payload = { 'responding_to' => responding_to, 'items' => items.first(MAX_ITEMS) }
      Redis::Alfred.setex(key(conversation), payload.to_json, TTL)
    end

    # Returns the items for this run and clears them. Buttons stashed for a different customer
    # message (a run that was discarded) are dropped instead of leaking into a later reply.
    def take(conversation, responding_to: nil)
      raw = Redis::Alfred.get(key(conversation))
      return if raw.blank?

      Redis::Alfred.delete(key(conversation))
      payload = JSON.parse(raw)
      payload['items'] if payload['responding_to'] == responding_to && payload['items'].present?
    end

    private

    def key(conversation)
      format(Redis::RedisKeys::CAPTAIN_QUICK_REPLIES, conversation_id: conversation.id)
    end
  end
end
