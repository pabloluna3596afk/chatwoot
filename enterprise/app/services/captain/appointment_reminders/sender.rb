# Sends one due reminder (the dispatcher already holds the row lock).
#
# Inside the 24 h window it is a single free-form message with [Confirmo] [Cambiar hora] [Cancelar cita]
# buttons (just the last two once the customer confirmed). Outside it, WhatsApp only accepts an approved
# template and bills it, so the template goes out only when the assistant has allow_paid_templates on;
# otherwise the reminder is skipped and one private note says why. Every send counts against the account's
# daily proactive cap, and a reminder over the cap waits (it is dropped if the appointment starts first).
class Captain::AppointmentReminders::Sender
  CONFIRMED = 'confirmed'.freeze

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
    settings.public_send("#{reminder.kind}?") && assistant.appointments_active_in?(conversation.inbox)
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

  def local_start
    @local_start ||= event.start_at.in_time_zone(zone)
  end

  def date_label
    weekday = I18n.t('captain.appointments.weekdays', locale: locale)[local_start.wday]
    format('%<weekday>s %<day>02d/%<month>02d', weekday: weekday, day: local_start.day, month: local_start.month)
  end

  def time_label
    local_start.strftime('%H:%M')
  end

  def when_label
    "#{date_label} #{time_label}"
  end

  def reminder_text
    translate(reminder.kind, name: contact.name, title: event.summary, when: when_label)
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
  # one appointment ("Cancelar cita · jue 16/01 10:00"); the choices resolve it back to this appointment.
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

  def short_date_time
    weekday = I18n.t('captain.appointments.weekdays_short', locale: locale)[local_start.wday]
    format('%<weekday>s %<day>02d/%<month>02d %<hour>s', weekday: weekday, day: local_start.day, month: local_start.month, hour: time_label)
  end

  def send_template
    return skip_with_note('not_sent_channel') unless conversation.inbox.channel_type == 'Channel::Whatsapp'
    return skip_with_note('not_sent_window') unless settings.allow_paid_templates?
    return skip_with_note('no_template') if settings.template_reminder.blank?

    entry = approved_template(settings.template_reminder)
    return skip_with_note('template_unavailable') if entry.blank?

    payload, text = template_message(entry)
    create_message(text, additional_attributes: { template_params: payload })
    finish
  end

  def approved_template(reference)
    Array(conversation.inbox.channel.message_templates).find do |entry|
      entry['name'] == reference['name'] &&
        entry['language'].to_s.casecmp?(reference['language']) &&
        entry['status'].to_s.casecmp?('approved')
    end
  end

  # Fills the template body variables in order: 1 name, 2 title, 3 date, 4 time, 5 assistant name
  # (the layout of the approved reminder templates); a variable we have no value for is sent as "-".
  def template_message(entry)
    body = Array(entry['components']).find { |component| component['type'].to_s.casecmp?('BODY') }
    text = body&.dig('text').to_s
    values = { '1' => contact.name, '2' => event.summary, '3' => date_label, '4' => time_label, '5' => assistant.name }
    parameters = text.scan(/\{\{\s*([^}\s]+)\s*\}\}/).flatten.uniq.index_with { |key| values[key].presence || '-' }
    payload = { name: entry['name'], namespace: entry['namespace'], language: entry['language'], category: entry['category'],
                processed_params: { body: parameters } }
    [payload, text.gsub(/\{\{\s*([^}\s]+)\s*\}\}/) { parameters[Regexp.last_match(1)] || '-' }.presence || entry['name']]
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
