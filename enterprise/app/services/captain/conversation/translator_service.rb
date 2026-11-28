class Captain::Conversation::TranslatorService
  pattr_initialize [:account!, { conversation_display_id: nil, message_id: nil }]

  def provider
    account.translation_service
  end

  def translate(text, target_language)
    return translate_with_google(text, target_language) if provider == 'google_translate'

    response = Captain::Llm::MessageTranslationService.new(
      account: account, text: text, target_language: target_language,
      conversation_display_id: conversation_display_id, message_id: message_id
    ).perform
    response[:message].presence
  end

  def language(text)
    return with_google_fallback('language detection') { google.detect(text) } if provider == 'google_translate'

    detection = Captain::Llm::LanguageDetectionService.new(
      account: account, text: text, conversation_display_id: conversation_display_id, message_id: message_id
    )
    language = detection.language
    @failed = true if detection.failed?
    language
  end

  def failed?
    @failed == true
  end

  private

  def translate_with_google(text, target_language)
    with_google_fallback('translation') { google.translate(text, target_language).presence }
  end

  def with_google_fallback(operation)
    yield
  rescue *Integrations::GoogleTranslate::CredentialsValidator::KEY_ERRORS => e
    @failed = true
    Rails.logger.warn("[AutoTranslate] Google #{operation} failed: #{e.class}")
    nil
  rescue StandardError => e
    @failed = true
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    nil
  end

  def google
    @google ||= Integrations::GoogleTranslate::ProcessorService.new(hook: account.google_translate_hook)
  end
end
