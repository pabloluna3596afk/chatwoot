class Captain::Llm::LanguageDetectionService < Captain::BaseTaskService
  pattr_initialize [:account!, :text!]

  def perform
    make_api_call(feature: 'language_detection', messages: messages, schema: Captain::Llm::LanguageDetectionSchema)
  end

  def language
    response = perform
    Rails.logger.warn("[AutoTranslate] language detection failed: #{response[:error]}") if response[:error]
    code = response.dig(:message, 'language')
    code unless code.blank? || code == 'und'
  end

  private

  def event_name
    'language_detection'
  end

  def counts_toward_usage?
    false
  end

  def messages
    [
      { role: 'system', content: <<~PROMPT },
        Identify the language of this customer support message. Return a BCP 47 language tag, including a region or script only when clear. Return und if it is too short or ambiguous.
      PROMPT
      { role: 'user', content: text }
    ]
  end
end
