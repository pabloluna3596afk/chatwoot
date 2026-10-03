# Sends one due reminder (the dispatcher already holds the row lock).
#
# Inside the 24 h window it is a single free-form message with [Confirmo] [Cambiar hora] [Cancelar cita]
# buttons (just the last two once the customer confirmed). Outside it, WhatsApp only accepts an approved
# template and bills it, so the template goes out only when the assistant has "paid templates" on (one switch for every Captain message that needs a template);
# otherwise the reminder is skipped and one private note says why. Every send counts against the account's
# daily proactive cap, and a reminder over the cap waits (it is dropped if the appointment starts first).
class Captain::AppointmentReminders::Sender
  CONFIRMED = 'confirmed'.freeze
  # The texts of a template saved before the variables could be chosen: numbered variables in a fixed order.
  LEGACY_TEMPLATE_PARAMS = {
    'body' => { '1' => '{{ contact.name }}', '2' => '{{ appointment.title }}', '3' => '{{ appointment.date }}',
                '4' => '{{ appointment.time }}', '5' => '{{ assistant.name }}' }
  }.freeze

  def initialize(reminder, now: Time.current)
    @reminder = reminder
    @now = now
  end

  # Returns :sent, :skipped or :waiting.
  def perform
    return skip('event_gone') unless upcoming_event?
    return skip('disabled') unless active?
    return :waiting unless cap.within_cap?

    conversation.can_reply? ? send_free_form : send_template
  end

  private

  attr_reader :reminder, :now

  delegate :calendar_event, :captain_assistant, :conversation, :account, to: :reminder
  alias event calendar_event
  alias assistant captain_assistant

  def settings
    assistant.appointments
  end

  def upcoming_event?
    event.present? && !event.discarded? && event.start_at.present? && event.start_at > now
  end

  def active?
    settings.reminder_enabled?(reminder.kind) && assistant.appointments_active_in?(conversation.inbox)
  end

  def cap
    @cap ||= Automations::ProactiveSendCap.new(account)
  end

  def locale
    account.locale
  end

  def zone
    @zone ||= Time.find_zone!(account.reporting_timezone.presence || Integrations::GoogleCalendar::Client::TIMEZONE)
  end

  def contact
    conversation.contact
  end

  def translate(key, **options)
    I18n.t("captain.appointment_reminders.#{key}", locale: locale, assistant: assistant.name, **options)
  end

  def button_label(button)
    I18n.t("captain.appointments.buttons.#{button}", locale: locale)
  end

  # "jueves 1 de octubre, 11:30"
  def when_label
    Captain::AppointmentFormat.long(event.start_at, locale: locale, zone: zone)
  end

  # Far ahead: "te recordamos tu cita ... para el jueves 1 de octubre, 11:30"; close: "tu cita es en unas 3 horas (...)".
  def reminder_text
    hours = settings.hours_before(reminder.kind)
    key = if hours >= 24 then 'reminder_far'
          elsif hours == 1 then 'reminder_near_one'
          else 'reminder_near'
          end
    translate(key, name: contact.name, title: event.summary, when: when_label, hours: hours)
  end

  def send_free_form
    buttons = Captain::QuickReplies.supported?(conversation.inbox)
    create_message(reminder_text + (buttons ? '' : translate('reply_hint', **button_labels)), **button_attributes(buttons))
    finish
  end

  def button_labels
    { confirm: button_label('confirm'), change: button_label('change_time'), cancel: button_label('cancel') }
  end

  # The value of each button carries the time, so a reply is unambiguous even if the customer has more than
  # one appointment ("Cancelar cita · jue 1 oct · 11:30"); the choices resolve it back to this appointment.
  def button_attributes(buttons)
    return {} unless buttons

    choices = button_choices
    Captain::QuickReplies.remember(conversation, choices.values.to_h { |choice| [choice[:value], { 'event_id' => event.google_event_id }] })
    { content_type: :input_select,
      content_attributes: { items: choices.values.map { |choice| Captain::QuickReplies.item(choice[:title], choice[:value]) } } }
  end

  def button_choices
    names = event.appointment_status == CONFIRMED ? %w[change_time cancel] : %w[confirm change_time cancel]
    names.index_with { |name| { title: button_label(name), value: "#{button_label(name)} · #{short_date_time}" } }
  end

  # "jue 1 oct · 11:30"
  def short_date_time
    Captain::AppointmentFormat.short(event.start_at, locale: locale, zone: zone)
  end

  def send_template
    return skip_with_note('not_sent_channel') unless conversation.inbox.channel_type == 'Channel::Whatsapp'
    return skip_with_note('not_sent_window') unless assistant.allow_paid_templates?
    return skip_with_note('no_template') if settings.template_reminder.blank?

    entry = Captain::TemplateMessage.approved(conversation.inbox, settings.template_reminder)
    return skip_with_note('template_unavailable') if entry.blank?

    drops = Captain::TemplateMessage.drops(conversation, assistant, appointment: appointment_drop)
    payload, text = Captain::TemplateMessage.build(entry, settings.template_reminder['processed_params'], drops,
                                                   fallback: LEGACY_TEMPLATE_PARAMS)
    create_message(text, additional_attributes: { template_params: payload })
    finish
  rescue Captain::TemplateMessage::MappingMismatch
    skip_with_note('template_changed')
  end

  # {{ appointment.date }} "jueves 1 de octubre", {{ appointment.time }} "11:30", {{ appointment.datetime }}
  # "jueves 1 de octubre, 11:30" and {{ appointment.title }}, in the language and timezone of the account.
  def appointment_drop
    {
      'date' => Captain::AppointmentFormat.day(event.start_at, locale: locale, zone: zone),
      'time' => Captain::AppointmentFormat.clock(event.start_at, zone: zone),
      'datetime' => when_label,
      'title' => event.summary
    }
  end

  def create_message(content, **attributes)
    conversation.messages.create!(
      message_type: :outgoing, account_id: account.id, inbox_id: conversation.inbox_id, sender: assistant,
      content: content, preserve_waiting_since: true, **attributes
    )
  end

  def finish
    cap.increment!
    reminder.update!(status: 'sent', sent_at: now, skipped_reason: nil)
    :sent
  end

  def skip(reason)
    reminder.update!(status: 'skipped', skipped_reason: reason)
    :skipped
  end

  def skip_with_note(reason_key)
    create_message(translate(reason_key, when: when_label), private: true)
    skip(reason_key)
  end
end
