class Captain::Conversation::ContactMessageTranslationService
  pattr_initialize [:message!, :target_language!]

  def perform
    return unless translatable_message?
    return if translation_available?

    save_translation(translate_content)
  end

  private

  delegate :conversation, to: :message

  def translatable_message?
    message.incoming? && !message.private? && message.content.present?
  end

  def translation_available?
    message.translations&.key?(target_language)
  end

  def translate_content
    language = Captain::Conversation::MessageLanguageService.new(conversation: conversation, message: message).perform
    return message.content if Captain::Llm::MessageTranslationService.same_language?(language, target_language)

    translator.translate(message.content, target_language)
  end

  def save_translation(translation)
    message.with_lock do
      next if message.deleted

      if translation.present?
        message.assign_attributes(
          translations: message.translations.to_h.merge(target_language => translation), translation_provider: translator.provider,
          translation_failed: nil
        )
      else
        message.translation_failed = true
      end
      message.save!
    end
  end

  def translator
    @translator ||= Captain::Conversation::TranslatorService.new(account: message.account, conversation_display_id: conversation.display_id)
  end
end
