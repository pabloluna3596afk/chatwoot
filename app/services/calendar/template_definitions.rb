class Calendar::TemplateDefinitions
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
  FUNCTIONS = { 'confirmation' => TEMPLATE_NAME, 'cancellation' => CANCEL_TEMPLATE_NAME, 'reminder' => REMINDER_TEMPLATE_NAME }.freeze
  VARIABLES = %w[nombre cita fecha hora].freeze
  ACTIONS = %w[confirm reschedule cancel].freeze

  def self.language(account)
    locale = account.locale.to_s[0, 2]
    TEMPLATES.key?(locale) ? locale : 'es'
  end

  def self.definition(function, language)
    DEFINITIONS.fetch(FUNCTIONS.fetch(function.to_s)).fetch(language)
  end
end
