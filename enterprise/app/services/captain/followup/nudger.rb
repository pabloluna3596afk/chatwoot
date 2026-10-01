# The "¿Sigues ahí?" of one pending conversation that Captain is handling.
#
# The customer owes a reply when the last public message (nudges aside) is Captain's. After
# inactivity_after_minutes Captain sends one short message with [Sí, sigo aquí] [Ya no, gracias]: free, inside
# the 24 h window and never outside it. After max_nudges (0-2) nudges, close_after_minutes after the last one with
# no answer, the conversation is resolved with a private note. Everything is derived from the messages, so a
# customer reply (a new last message) starts over and running it twice sends nothing twice.
class Captain::Followup::Nudger
  NUDGE_MARK = 'nudge'.freeze

  def initialize(conversation, assistant, now: Time.current)
    @conversation = conversation
    @assistant = assistant
    @now = now
  end

  # Returns :nudged, :closed or nil.
  def perform
    result = conversation.with_lock do
      conversation.reload
      reset

      next unless conversation.captain_attended? && awaiting_customer?

      if nudge_due?
        nudge
      elsif close_due?
        close
      end
    end
    announce_resolution if result == :closed
    result
  end

  private

  attr_reader :conversation, :assistant, :now

  def settings
    assistant.followup
  end

  def account
    conversation.account
  end

  def locale
    account.locale
  end

  # The last public message that is not one of our nudges.
  def last_message
    @last_message ||= conversation.messages.where(private: false, message_type: %i[incoming outgoing])
                                  .select { |message| !nudge?(message) }
                                  .max_by(&:created_at)
  end

  def nudge?(message)
    message.content_attributes['captain_followup'] == NUDGE_MARK
  end

  def awaiting_customer?
    last_message.present? && last_message.outgoing? && last_message.sender_type == 'Captain::Assistant' &&
      last_message.sender_id == assistant.id
  end

  def nudges
    @nudges ||= conversation.messages.where(private: false, message_type: :outgoing)
                            .where('created_at > ?', last_message.created_at).select { |message| nudge?(message) }
  end

  def last_activity
    nudges.map(&:created_at).max || last_message.created_at
  end

  def nudge_due?
    nudges.size < settings.max_nudges && now - last_activity >= settings.inactivity_after_minutes.minutes &&
      conversation.can_reply? && cap.within_cap?
  end

  def close_due?
    nudges.any? && nudges.size >= settings.max_nudges && now - last_activity >= settings.close_after_minutes.minutes
  end

  def cap
    @cap ||= Automations::ProactiveSendCap.new(account)
  end

  def translate(key, **options)
    I18n.t("captain.followup.#{key}", locale: locale, assistant: assistant.name, **options)
  end

  def nudge
    buttons = Captain::QuickReplies.supported?(conversation.inbox)
    content = translate('nudge') + (buttons ? '' : translate('nudge_hint', continue: translate('continue_button'), stop: translate('stop_button')))
    conversation.messages.create!(
      { message_type: :outgoing, account_id: account.id, inbox_id: conversation.inbox_id, sender: assistant,
        content: content, preserve_waiting_since: true,
        content_attributes: { 'captain_followup' => NUDGE_MARK } }.merge(buttons ? button_attributes : {})
    )
    cap.increment!
    :nudged
  end

  def button_attributes
    items = { 'continue' => translate('continue_button'), 'stop' => translate('stop_button') }
    Captain::QuickReplies.remember(conversation, items.to_h { |action, title| [title, { 'followup' => action }] })
    { content_type: :input_select,
      content_attributes: { 'captain_followup' => NUDGE_MARK,
                            'items' => items.values.map { |title| Captain::QuickReplies.item(title, title) } } }
  end

  def reset
    @last_message = nil
    @nudges = nil
  end

  def close
    Current.executed_by = assistant
    conversation.with_captain_activity_context(reason: 'no reply to the follow-up', reason_type: :inference) do
      create_note
      create_resolution_message
      conversation.resolved!
      mark_closed
    end
    :closed
  end

  def announce_resolution
    Captain::ConversationEvents.resolved(conversation: conversation, assistant: assistant,
                                         source: Captain::ConversationEvents::Sources::TIME_BASED, at: now)
  end

  def create_note
    conversation.messages.create!(
      message_type: :outgoing, private: true, sender: assistant, account_id: account.id,
      inbox_id: conversation.inbox_id, content: translate('closed_note')
    )
  end

  # Same optional goodbye the assistant already sends when it closes for inactivity, only inside the window.
  def create_resolution_message
    return unless assistant.send_inactivity_resolution_message? && conversation.can_reply?

    conversation.messages.create!(
      message_type: :outgoing, sender: assistant, account_id: account.id, inbox_id: conversation.inbox_id,
      content: assistant.config['resolution_message'].presence || I18n.t('conversations.activity.auto_resolution_message', locale: locale)
    )
  end

  # What the re-engagement later needs to find the conversation.
  def mark_closed
    attributes = conversation.additional_attributes || {}
    conversation.update!(additional_attributes: attributes.merge(
      Captain::Followup::Reengager::STATE_KEY => { 'closed_at' => now.utc.iso8601, 'assistant_id' => assistant.id }
    ))
  end
end
