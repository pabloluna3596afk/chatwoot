# Buttons ("input_select" items) that a Captain tool wants on the assistant's next reply.
#
# The model never writes the buttons: a tool stashes them here for the conversation, and when the
# response job posts the model's reply it takes them and sends one input_select message (the
# model's text is the question, the items are the buttons). WhatsApp turns up to 3 items into
# reply buttons and more into a list; the web widget renders them as buttons.
#
# A tapped button comes back as the customer's message, with the item's value as its text, so the
# values are readable ("Sí, reservar · jue 16/01 10:00"). Each stash can also remember what a value
# stands for (a start time, an appointment id); tools resolve a reply through .choice. That memory
# outlives the buttons being sent and lasts as long as the WhatsApp service window, so a customer who
# answers later the same day does not have to choose again (every extra round trip is a paid message
# and an LLM call). Tools still re-check that the slot is free, so an old reply is never unsafe.
class Captain::QuickReplies
  BUTTONS_TTL = 10.minutes.to_i
  CHOICES_TTL = 24.hours.to_i
  MAX_ITEMS = 10
  MAX_VALUE_LENGTH = 256
  INTERACTIVE_CHANNELS = %w[Channel::WebWidget Channel::Telegram Channel::FacebookPage Channel::Line].freeze

  class << self
    # Whether the inbox renders input_select as buttons. Others get numbered text from the tools.
    def supported?(inbox)
      return inbox.channel.provider == 'whatsapp_cloud' if inbox.channel_type == 'Channel::Whatsapp'

      INTERACTIVE_CHANNELS.include?(inbox.channel_type)
    end

    def item(title, value)
      { 'title' => title, 'value' => value.to_s.truncate(MAX_VALUE_LENGTH, omission: '') }
    end

    # Replaces the buttons waiting to be sent (only the latest tool call's buttons go out) and adds
    # what their values stand for: { 'value' => { 'start' => iso, 'event_id' => id } }.
    def stash(conversation, items, responding_to: nil, choices: {})
      payload = { 'responding_to' => responding_to, 'items' => items.first(MAX_ITEMS) }
      Redis::Alfred.setex(key(conversation), payload.to_json, BUTTONS_TTL)
      remember(conversation, choices) if choices.present?
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

    # What a customer reply stands for, or nil when it is not one of the recent buttons (or expired).
    def choice(conversation, value)
      return if value.blank?

      choices(conversation)[value.to_s.strip]
    end

    # Adds what button values stand for, without stashing buttons (used by messages that are posted directly,
    # such as the appointment reminders). Keeps earlier choices and renews the 24 h.
    def remember(conversation, new_choices)
      merged = choices(conversation).merge(new_choices.transform_keys(&:to_s))
      Redis::Alfred.setex(choices_key(conversation), merged.to_json, CHOICES_TTL)
    end

    private

    def choices(conversation)
      raw = Redis::Alfred.get(choices_key(conversation))
      raw.present? ? JSON.parse(raw) : {}
    end

    def key(conversation)
      format(Redis::RedisKeys::CAPTAIN_QUICK_REPLIES, conversation_id: conversation.id)
    end

    def choices_key(conversation)
      format(Redis::RedisKeys::CAPTAIN_QUICK_REPLY_CHOICES, conversation_id: conversation.id)
    end
  end
end
