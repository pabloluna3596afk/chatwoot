# One paid WhatsApp template for a conversation that Captain closed for inactivity (Captain::Followup::Nudger) and
# whose customer never answered, once the 24 h window has closed. Meta bills it, so it needs the assistant's
# "paid templates" switch (off by default), the re-engagement switch and an approved template picked in the
# settings. At most one attempt per conversation and one per contact every 7 days; when it cannot be sent (switch
# off, no template) one private note says why and the conversation is not tried again.
class Captain::Followup::Reengager
  STATE_KEY = 'captain_followup'.freeze
  COOLDOWN = 7.days
  # The texts of a template saved before the variables could be chosen: 1 the customer, 2 the assistant.
  LEGACY_TEMPLATE_PARAMS = { 'body' => { '1' => '{{ contact.name }}', '2' => '{{ assistant.name }}' } }.freeze
  STATE_PATH = "conversations.additional_attributes -> '#{STATE_KEY}'".freeze

  # Closed by Captain in the last 7 days and not attempted yet.
  def self.candidates(inbox, now: Time.current)
    inbox.conversations.resolved
         .where("#{STATE_PATH} ->> 'closed_at' >= ?", (now - COOLDOWN).utc.iso8601)
         .where("#{STATE_PATH} ->> 'reengagement' IS NULL")
         .order(:updated_at)
  end

  def initialize(conversation, assistant, now: Time.current)
    @conversation = conversation
    @assistant = assistant
    @now = now
  end

  # Returns :sent, :skipped or nil (not yet: the window is still open, or the daily cap is reached).
  def perform
    conversation.with_lock do
      conversation.reload
      next unless due?

      deliver
    end
  end

  private

  attr_reader :conversation, :assistant, :now

  delegate :account, :contact, to: :conversation

  def settings
    assistant.followup
  end

  def state
    (conversation.additional_attributes || {})[STATE_KEY] || {}
  end

  def due?
    conversation.resolved? && state['closed_at'].present? && state['reengagement'].blank? && !conversation.can_reply?
  end

  def translate(key)
    I18n.t("captain.followup.#{key}", locale: account.locale, assistant: assistant.name)
  end

  def deliver
    return skip('cooldown') if contacted_recently?
    return skip('channel') unless conversation.inbox.channel_type == 'Channel::Whatsapp'
    return skip_with_note('reengagement_paid_off', 'paid_templates_off') unless assistant.allow_paid_templates?
    return skip_with_note('reengagement_no_template', 'no_template') if settings.reengagement_template.blank?

    entry = Captain::TemplateMessage.approved(conversation.inbox, settings.reengagement_template)
    return skip_with_note('reengagement_template_unavailable', 'template_unavailable') if entry.blank?
    return unless cap.within_cap?

    send_template(entry)
  end

  def cap
    @cap ||= Automations::ProactiveSendCap.new(account)
  end

  def contacted_recently?
    contact.conversations.where.not(id: conversation.id)
           .where("#{STATE_PATH} -> 'reengagement' ->> 'status' = 'sent'")
           .where("#{STATE_PATH} -> 'reengagement' ->> 'at' >= ?", (now - COOLDOWN).utc.iso8601).exists?
  end

  def send_template(entry)
    drops = Captain::TemplateMessage.drops(conversation, assistant)
    payload, text = Captain::TemplateMessage.build(entry, settings.reengagement_template['processed_params'], drops,
                                                   fallback: LEGACY_TEMPLATE_PARAMS)
    create_message(text, additional_attributes: { template_params: payload })
    cap.increment!
    record('at' => now.utc.iso8601, 'status' => 'sent')
    :sent
  rescue Captain::TemplateMessage::MappingMismatch
    skip_with_note('reengagement_template_changed', 'template_changed')
  end

  def skip(reason)
    record('at' => now.utc.iso8601, 'status' => 'skipped', 'reason' => reason)
    :skipped
  end

  def skip_with_note(note_key, reason)
    create_message(translate(note_key), private: true)
    skip(reason)
  end

  def record(outcome)
    attributes = conversation.additional_attributes || {}
    conversation.update!(additional_attributes: attributes.merge(STATE_KEY => state.merge('reengagement' => outcome)))
  end

  def create_message(content, **attributes)
    conversation.messages.create!(
      message_type: :outgoing, account_id: account.id, inbox_id: conversation.inbox_id, sender: assistant,
      content: content, preserve_waiting_since: true, **attributes
    )
  end
end
