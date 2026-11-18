require 'uri'

# Validates and sends one due reminder, locking the event before its reminder row.
#
# Inside the 24 h window it is a single free-form message with [Confirmo] [Cambiar hora] [Cancelar cita]
# buttons (just the last two once the customer confirmed). Outside it, the template needs the assistant's
# "paid templates" switch. Otherwise the reminder is skipped with one private note. Outside customer hours
# it waits (or is dropped if the appointment starts first).
class Captain::AppointmentReminders::Sender
  CONFIRMED = 'confirmed'.freeze
  # The texts of a template saved before the variables could be chosen: numbered variables in a fixed order.
  LEGACY_TEMPLATE_PARAMS = Captain::AppointmentReminders::Readiness::LEGACY_TEMPLATE_PARAMS

  def initialize(reminder, now: Time.current)
    @reminder = reminder
    @now = now
  end

  # Returns :sent, :skipped or :waiting.
  def perform
    event.with_lock do
      return :skipped unless reminder.reload.pending?
      return :waiting if reminder.scheduled_at > now
      return skip('event_gone') unless upcoming_event?
      return :waiting unless refresh_event

      reminder.with_lock { deliver }
    end
  end

  private

  def refresh_event
    Integrations::GoogleCalendar::EventService.new(account: account, user: nil, connection: event.calendar_connection).reconcile!(event)
    true
  rescue Integrations::GoogleCalendar::Client::Error, Timeout::Error, SocketError, SystemCallError => e
    Rails.logger.warn("Google Calendar reminder validation failed for event #{event.id}: #{e.class}")
    false
  end

  def deliver
    return :skipped unless reminder.pending?
    return :waiting if reminder.scheduled_at > now
    return skip('event_gone') unless upcoming_event?
    return skip('disabled') unless active?

    return send_agent_note if human_conversation?

    conversation.can_reply? ? send_free_form : send_template
  end

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

  def human_conversation?
    conversation.assignee_id.present? && conversation.open? && conversation.can_reply?
  end

  def locale
    account.locale
  end

  def zone
    @zone ||= Integrations::GoogleCalendar::Timezone.for(account)
  end

  def translate(key, **options)
    I18n.t("captain.appointment_reminders.#{key}", locale: locale, assistant: assistant.name, **options)
  end

  def button_label(button)
    I18n.t("captain.appointments.buttons.#{button}", locale: locale)
  end

  # "jueves 1 de octubre, 11:30"
  def when_label
    appointment_format.long
  end

  # Far ahead: "te recordamos tu cita ... para el jueves 1 de octubre, 11:30"; close: "tu cita es en unas 3 horas (...)".
  def reminder_text
    hours = settings.hours_before(reminder.kind)
    key = if delayed? || hours >= 24 then 'reminder_far'
          elsif hours == 1 then 'reminder_near_one'
          else 'reminder_near'
          end
    translate(key, name: conversation.contact.name, title: event.summary, when: when_label, hours: hours)
  end

  def delayed?
    now - reminder.scheduled_at > 15.minutes
  end

  def send_free_form
    return :waiting unless Calendar::CustomerReminders::Schedule.sending_hours?(account, now)

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
    names.index_with { |name| { title: button_label(name), value: "#{button_label(name)} · #{appointment_format.short}" } }
  end

  def send_template
    readiness = Captain::AppointmentReminders::Readiness.new(assistant, conversation.inbox)
    reason = readiness.outside_window_reason
    return skip_with_note(reason) if reason

    deliver_template(readiness.entry)
  end

  def deliver_template(entry)
    return :waiting unless Calendar::CustomerReminders::Schedule.sending_hours?(account, now)

    cap = Captain::TemplateDailyCap.new(account, now: now)
    return skip_with_note('captain_template_cap_reached') unless cap.reserve!

    deliver_reserved_template(entry, cap)
  end

  def deliver_reserved_template(entry, cap)
    drops = Captain::TemplateMessage.drops(conversation, assistant, appointment: appointment_format.drop)
    payload, text = Captain::TemplateMessage.build(entry, settings.template_reminder['processed_params'], drops,
                                                   fallback: LEGACY_TEMPLATE_PARAMS)
    create_message(text, additional_attributes: { template_params: payload })
    finish
  rescue Variables::DeliveryRenderer::Error => e
    cap&.release! unless @template_message_created
    Captain::VariableDiagnostics.record(assistant, e, template: settings.template_reminder)
    skip_with_note('template_variables_missing')
  rescue Captain::TemplateMessage::MappingMismatch
    cap&.release! unless @template_message_created
    skip_with_note('template_changed')
  rescue StandardError
    cap&.release! unless @template_message_created
    raise
  end

  # {{ appointment.date }} "jueves 1 de octubre", {{ appointment.time }} "11:30", {{ appointment.datetime }}
  # "jueves 1 de octubre, 11:30" and {{ appointment.title }}, in the language and timezone of the account.
  def create_message(content, **attributes)
    message = conversation.messages.build(
      message_type: :outgoing, account_id: account.id, inbox_id: conversation.inbox_id, sender: assistant,
      content: content, preserve_waiting_since: true, **attributes
    )
    message.variables_resolved! if attributes[:additional_attributes]&.with_indifferent_access&.key?(:template_params)
    message.save!
    @template_message_created = true if attributes[:additional_attributes]&.with_indifferent_access&.key?(:template_params)
    message
  end

  def finish
    reminder.update!(status: 'sent', sent_at: now, skipped_reason: nil)
    :sent
  end

  def appointment_format
    @appointment_format ||= Captain::AppointmentReminders::Format.new(event, locale: locale, zone: zone)
  end

  def skip(reason)
    reminder.update!(status: 'skipped', skipped_reason: reason)
    :skipped
  end

  def skip_with_note(reason_key)
    create_message(translate(reason_key, when: when_label), private: true)
    skip(reason_key)
  end

  def send_agent_note
    create_message(agent_note_content, private: true)
    skip('agent_note')
  end

  def agent_note_content
    "#{agent_note_intro}\n\n#{agent_copy_text}"
  end

  def agent_note_intro
    key = event.appointment_status == CONFIRMED ? 'agent_note' : 'agent_note_unconfirmed'
    translate(key, mention: assignee_mention, today: agent_note_today, title: event.summary, when: when_label)
  end

  def assignee_mention
    name = conversation.assignee.name
    encoded_name = URI::DEFAULT_PARSER.escape(name, /[^A-Za-z0-9\-_.!~*'()]/)
    "[@#{name}](mention://user/#{conversation.assignee_id}/#{encoded_name})"
  end

  def agent_note_today
    return '' unless event.start_at.in_time_zone(zone).to_date == now.in_time_zone(zone).to_date

    translate('agent_note_today')
  end

  def agent_copy_text
    translate(agent_copy_key, name: conversation.contact.name, title: event.summary, when: when_label)
  end

  def agent_copy_key
    name = conversation.contact.name.blank? ? '_no_name' : ''
    confirmation = event.appointment_status == CONFIRMED ? '' : '_unconfirmed'
    "agent_copy_text#{name}#{confirmation}"
  end
end
