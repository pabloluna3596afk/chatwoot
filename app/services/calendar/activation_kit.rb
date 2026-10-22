# What an account needs so appointments work from day one: the attributes of the contact (Calendar::AppointmentAttributes)
# and, on the WhatsApp Cloud inboxes the administrator picks, confirmation, cancellation and reminder templates sent to Meta
# for review.
# Idempotent: what already exists is reused, and a template Meta rejected is the only one sent again.
#
# The templates use named variables the catalog already fills by name ({{nombre}}, {{cita}}, {{fecha}}, {{hora}}), so
# no choices have to be stored for it. Its status comes from the templates Meta syncs into the channel.
class Calendar::ActivationKit
  TEMPLATE_NAME = 'cita_confirmacion'.freeze
  CATEGORY = 'UTILITY'.freeze
  TEMPLATES = {
    'es' => {
      body: 'Hola {{nombre}}, tu cita "{{cita}}" quedó agendada para el {{fecha}} a las {{hora}}. ¿Confirmas tu asistencia?',
      examples: %w[María Consulta 23/08/2026 10:00],
      buttons: %w[Confirmar Reagendar Cancelar]
    },
    'en' => {
      body: 'Hi {{nombre}}, your appointment "{{cita}}" is booked for {{fecha}} at {{hora}}. Can you confirm you will attend?',
      examples: %w[Maria Consultation 08/23/2026 10:00],
      buttons: %w[Confirm Reschedule Cancel]
    }
  }.freeze
  CANCEL_TEMPLATE_NAME = 'cita_cancelacion'.freeze
  CANCEL_TEMPLATES = {
    'es' => {
      body: 'Hola {{nombre}}, tu cita "{{cita}}" del {{fecha}} a las {{hora}} fue cancelada. ' \
            'Si quieres agendar otra, respóndenos por aquí.',
      examples: %w[María Consulta 23/08/2026 10:00],
      buttons: []
    },
    'en' => {
      body: 'Hi {{nombre}}, your appointment "{{cita}}" on {{fecha}} at {{hora}} was cancelled. ' \
            'If you want to book another one, reply here.',
      examples: %w[Maria Consultation 08/23/2026 10:00],
      buttons: []
    }
  }.freeze
  REMINDER_TEMPLATE_NAME = 'cita_recordatorio'.freeze
  REMINDER_TEMPLATES = {
    'es' => {
      body: 'Hola {{nombre}}, te recordamos tu cita "{{cita}}" para el {{fecha}} a las {{hora}}. ¿Sigues pudiendo asistir?',
      examples: TEMPLATES['es'][:examples], buttons: TEMPLATES['es'][:buttons]
    },
    'en' => {
      body: 'Hi {{nombre}}, this is a reminder of your appointment "{{cita}}" on {{fecha}} at {{hora}}. Can you still attend?',
      examples: TEMPLATES['en'][:examples], buttons: TEMPLATES['en'][:buttons]
    }
  }.freeze
  DEFINITIONS = { TEMPLATE_NAME => TEMPLATES, CANCEL_TEMPLATE_NAME => CANCEL_TEMPLATES,
                  REMINDER_TEMPLATE_NAME => REMINDER_TEMPLATES }.freeze
  REPLY_TEMPLATE_NAMES = [TEMPLATE_NAME, REMINDER_TEMPLATE_NAME].freeze
  NOT_REVIEWABLE = %w[PENDING APPROVED IN_APPEAL].freeze

  def initialize(account)
    @account = account
  end

  def language
    TEMPLATES.key?(@account.locale.to_s[0, 2]) ? @account.locale.to_s[0, 2] : 'es'
  end

  def status
    { attributes: provisioner.status, template: template_summary(TEMPLATE_NAME),
      cancel_template: template_summary(CANCEL_TEMPLATE_NAME).except(:buttons),
      reminder_template: template_summary(REMINDER_TEMPLATE_NAME), reminder_enabled: @account.customer_reminders_enabled == true,
      inboxes: whatsapp_inboxes.map { |inbox| inbox_status(inbox) } }
  end

  # Creates the attributes (the ones the administrator already chose, or all of them) and sends the template to the
  # given inboxes. Returns the same shape as `status`, plus the result of each template.
  def apply(inbox_ids: [])
    provisioner.perform(keys: attribute_keys)
    chosen = whatsapp_inboxes.select { |inbox| inbox_ids.map(&:to_i).include?(inbox.id) }
    results = chosen.to_h do |inbox|
      [inbox.id, submit(inbox, TEMPLATE_NAME).merge(
        cancel: submit(inbox, CANCEL_TEMPLATE_NAME), reminder: submit(inbox, REMINDER_TEMPLATE_NAME)
      )]
    end
    status.merge(results: results)
  end

  private

  def template_summary(name)
    definition = definition(name)
    { name: name, language: language, category: CATEGORY, body: definition[:body], buttons: definition[:buttons] }
  end

  def definition(name)
    DEFINITIONS.fetch(name).fetch(language)
  end

  def provisioner
    @provisioner ||= Calendar::AppointmentAttributes::Provisioner.new(account: @account)
  end

  def attribute_keys
    provisioner.status['keys'] || Calendar::AppointmentAttributes::Definitions::TYPES.keys
  end

  def whatsapp_inboxes
    @account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).select do |inbox|
      inbox.channel.provider == 'whatsapp_cloud'
    end
  end

  def template_of(inbox, name)
    Array(inbox.channel.message_templates).find do |template|
      template.is_a?(Hash) && template['name'] == name && template['language'] == language
    end
  end

  def inbox_status(inbox)
    { id: inbox.id, name: inbox.name }.merge(
      template_state(inbox, TEMPLATE_NAME),
      template_state(inbox, CANCEL_TEMPLATE_NAME, prefix: 'cancel_'),
      template_state(inbox, REMINDER_TEMPLATE_NAME, prefix: 'reminder_')
    )
  end

  def template_state(inbox, name, prefix: '')
    template = template_of(inbox, name)
    { "#{prefix}status".to_sym => template ? template['status'].to_s.downcase : 'missing',
      "#{prefix}rejected_reason".to_sym => rejected_reason_of(template) }
  end

  def rejected_reason_of(template)
    reason = template && template['rejected_reason'].presence
    reason unless reason == 'NONE'
  end

  def submit(inbox, name)
    existing = template_of(inbox, name)
    return { status: existing['status'].to_s.downcase } if existing && NOT_REVIEWABLE.include?(existing['status'].to_s.upcase)

    created = Whatsapp::TemplateManagementService.new(inbox.channel).create(**template_request(name))
    { status: created[:status].to_s.downcase.presence || 'pending' }
  rescue Whatsapp::TemplateManagementService::Error => e
    { status: 'error', code: e.code, detail: e.detail }
  rescue Whatsapp::TemplateComponentsBuilder::Invalid => e
    { status: 'error', code: e.code }
  end

  def template_request(name)
    definition = definition(name)
    builder = Whatsapp::TemplateComponentsBuilder.new(
      body: { text: definition[:body], examples: definition[:examples] },
      buttons: definition[:buttons].map { |text| { type: 'QUICK_REPLY', text: text } },
      category: CATEGORY
    )
    { name: name, language: language, category: CATEGORY, components: builder.components, parameter_format: builder.parameter_format }
  end
end
