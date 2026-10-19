class Onboarding::CaptainDraftTemplates
  BUSINESS_INSTRUCTIONS = {
    'appointments' => 'Explica los servicios confirmados y ayuda a solicitar una cita con una persona. No confirmes reservas ni disponibilidad.',
    'commerce' => 'Orienta sobre el catálogo y las condiciones confirmadas. No prometas existencias, entregas ni pagos.',
    'services' => 'Explica el alcance de los servicios confirmados y recoge la consulta inicial para que una persona prepare la cotización.',
    'other' => 'Ofrece información confirmada sobre el negocio y deriva a una persona cuando necesites más datos.'
  }.freeze
  TONES = {
    'friendly' => 'Usa un tono cercano, amable y claro.',
    'professional' => 'Usa un tono profesional, respetuoso y claro.',
    'brief' => 'Usa un tono breve y directo, con respuestas cortas y claras.'
  }.freeze
  GUARDRAILS = [
    'No inventes precios, horarios, políticas ni respuestas comerciales. Usa solo información confirmada por el negocio.',
    'Si no tienes información suficiente, dilo y ofrece ayuda de una persona. No prometas acciones que no puedes realizar.'
  ].freeze

  # Extension point for future AI generation: replace this local composition while
  # preserving the draft service's transaction, limits and explicit activation.
  def self.instructions(account:, goal:, tone:)
    [
      BUSINESS_INSTRUCTIONS.fetch(account.custom_attributes.fetch('business_type', 'other')),
      TONES.fetch(tone),
      "Responde en el idioma de la cuenta: #{account.locale}.",
      "Objetivo indicado por el negocio:\n#{goal}"
    ]
  end
end
