# Structural preparation of saved settings, per inbox. Concrete values and the reply
# window are checked again at dispatch; this is never a guarantee of delivery.
class Captain::AppointmentReminders::Readiness
  LEGACY_TEMPLATE_PARAMS = {
    'body' => { '1' => '{{ contact.name }}', '2' => '{{ appointment.title }}', '3' => '{{ appointment.date }}',
                '4' => '{{ appointment.time }}', '5' => '{{ assistant.name }}' }
  }.freeze

  def initialize(assistant, inbox)
    @assistant = assistant
    @inbox = inbox
  end

  def to_h
    status = if !assistant.appointments_active_in?(inbox) || !assistant.appointments.any_reminder_enabled?
               'disabled'
             else
               outside_window_reason || 'ready'
             end
    { inbox_id: inbox.id, inbox_name: inbox.name, status: status, missing: status == 'template_changed' ? missing : [] }
  end

  # These codes are also the sender's skipped_reason and private-note keys.
  def outside_window_reason
    return 'not_sent_channel' unless inbox.channel_type == 'Channel::Whatsapp'
    return 'not_sent_window' unless assistant.allow_paid_templates?
    return 'no_template' if reference.blank?
    return 'template_unavailable' if entry.blank?
    return 'template_changed' if missing.any?

    nil
  end

  def entry
    @entry ||= Captain::TemplateMessage.approved(inbox, reference)
  end

  private

  attr_reader :assistant, :inbox

  def reference
    assistant.appointments.template_reminder
  end

  def missing
    params = reference['processed_params'] || LEGACY_TEMPLATE_PARAMS
    Captain::TemplateMessage.unmapped(entry, params)
  end
end
