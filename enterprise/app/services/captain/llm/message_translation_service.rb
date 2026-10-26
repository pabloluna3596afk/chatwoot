class Captain::Llm::MessageTranslationService < Captain::BaseTaskService
  LANGUAGE_NAMES = YAML.load_file(Rails.root.join('config/languages/language_map.yml')).freeze
  CONTROL_CHARACTERS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F]/

  pattr_initialize [:account!, :text!, :target_language!, { conversation_display_id: nil }]

  def self.same_language?(first, second)
    first.to_s.split(/[-_]/).first == second.to_s.split(/[-_]/).first
  end

  def perform
    response = make_api_call(feature: 'message_translation', messages: messages, schema: Captain::Llm::MessageTranslationSchema)
    return response if response[:error]

    response.merge(message: response[:message]['translation'].to_s.gsub(CONTROL_CHARACTERS, ''))
  end

  private

  def event_name
    'message_translation'
  end

  def messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: text }
    ]
  end

  def system_prompt
    <<~PROMPT
      Translate the message into #{language_name}. Preserve meaning, tone, line breaks, URLs, numbers, names, product terms,
      markdown, emojis, and template variables. Return unchanged if already in that language.
    PROMPT
  end

  def language_name
    LANGUAGE_NAMES[target_language.to_s.tr('-', '_')] || target_language
  end
end
