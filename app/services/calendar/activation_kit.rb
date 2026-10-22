# What an account needs so appointments work from day one: the attributes of the contact (Calendar::AppointmentAttributes)
# and, on the WhatsApp Cloud inboxes the administrator picks, the confirmation template sent to Meta for review.
# Idempotent: what already exists is reused, and a template Meta rejected is the only one sent again.
#
# The template uses named variables the catalog already fills by name ({{nombre}}, {{cita}}, {{fecha}}, {{hora}}), so
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
  NOT_REVIEWABLE = %w[PENDING APPROVED IN_APPEAL].freeze

  def initialize(account)
    @account = account
  end

  def language
    TEMPLATES.key?(@account.locale.to_s[0, 2]) ? @account.locale.to_s[0, 2] : 'es'
  end

  def status
    { attributes: provisioner.status, template: template_summary, inboxes: whatsapp_inboxes.map { |inbox| inbox_status(inbox) } }
  end

  # Creates the attributes (the ones the administrator already chose, or all of them) and sends the template to the
  # given inboxes. Returns the same shape as `status`, plus the result of each template.
  def apply(inbox_ids: [])
    provisioner.perform(keys: attribute_keys)
    results = whatsapp_inboxes.select { |inbox| inbox_ids.map(&:to_i).include?(inbox.id) }.to_h { |inbox| [inbox.id, submit(inbox)] }
    status.merge(results: results)
  end

  private

  def template_summary
    { name: TEMPLATE_NAME, language: language, category: CATEGORY, body: definition[:body], buttons: definition[:buttons] }
  end

  def definition
    TEMPLATES.fetch(language)
  end

  def provisioner
    @provisioner ||= Calendar::AppointmentAttributes::Provisioner.new(account: @account)
  end

  def attribute_keys
    provisioner.status['keys'] || Calendar::AppointmentAttributes::Definitions::TYPES.keys
  end

  def whatsapp_inboxes
    @account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).select { |inbox| inbox.channel.provider == 'whatsapp_cloud' }
  end

  def template_of(inbox)
    Array(inbox.channel.message_templates).find do |template|
      template.is_a?(Hash) && template['name'] == TEMPLATE_NAME && template['language'] == language
    end
  end

  def inbox_status(inbox)
    template = template_of(inbox)
    { id: inbox.id, name: inbox.name, status: template ? template['status'].to_s.downcase : 'missing',
      rejected_reason: rejected_reason_of(template) }
  end

  def rejected_reason_of(template)
    reason = template && template['rejected_reason'].presence
    reason unless reason == 'NONE'
  end

  def submit(inbox)
    existing = template_of(inbox)
    return { status: existing['status'].to_s.downcase } if existing && NOT_REVIEWABLE.include?(existing['status'].to_s.upcase)

    created = Whatsapp::TemplateManagementService.new(inbox.channel).create(**template_request)
    { status: created[:status].to_s.downcase.presence || 'pending' }
  rescue Whatsapp::TemplateManagementService::Error => e
    { status: 'error', code: e.code, detail: e.detail }
  rescue Whatsapp::TemplateComponentsBuilder::Invalid => e
    { status: 'error', code: e.code }
  end

  def template_request
    builder = Whatsapp::TemplateComponentsBuilder.new(
      body: { text: definition[:body], examples: definition[:examples] },
      buttons: definition[:buttons].map { |text| { type: 'QUICK_REPLY', text: text } },
      category: CATEGORY
    )
    { name: TEMPLATE_NAME, language: language, category: CATEGORY, components: builder.components, parameter_format: builder.parameter_format }
  end
end
