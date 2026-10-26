class Captain::Conversation::TranslatorService
  pattr_initialize [:account!, { conversation_display_id: nil }]

  def provider
    account.translation_service
  end

  def translate(text, target_language)
    return translate_with_google(text, target_language) if provider == 'google_translate'

    response = Captain::Llm::MessageTranslationService.new(
      account: account, text: text, target_language: target_language, conversation_display_id: conversation_display_id
    ).perform
    response[:message].presence
  end

  def language(text)
    return google.detect(text) if provider == 'google_translate'

    Captain::Llm::LanguageDetectionService.new(account: account, text: text).language
  rescue Google::Cloud::Error => e
    Rails.logger.warn("[AutoTranslate] Google language detection failed: #{e.message}")
    nil
  end

  private

  def translate_with_google(text, target_language)
    google.translate(text, target_language).presence
  rescue Google::Cloud::Error => e
    Rails.logger.warn("[AutoTranslate] Google translation failed: #{e.message}")
    nil
  end

  def google
    @google ||= Integrations::GoogleTranslate::ProcessorService.new(hook: account.google_translate_hook)
  end
end
