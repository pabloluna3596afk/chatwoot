class Captain::Conversation::AgentMessageTranslationService
  include EmailHelper

  pattr_initialize [:message!]

  def perform
    return unless message.outgoing? && !message.private? && message.content.present?

    detect_contact_language
    translate_reply if conversation.language.present?
    message.content_attributes.delete('translation_pending')
    message.content_attributes['translation_status'] = message.translation_failed == true ? 'failed' : 'completed'
    message.save!
  end

  private

  delegate :conversation, :account, :inbox, to: :message

  def detect_contact_language
    contact_message = conversation.messages.incoming.where(content_type: %w[text incoming_email], private: false)
                                  .where.not(content: [nil, '']).order(:id).last
    Captain::Conversation::MessageLanguageService.new(conversation: conversation, message: contact_message).perform if contact_message
  end

  def translate_reply
    return if Captain::Llm::MessageTranslationService.same_language?(reply_language, conversation.language)

    translated = translator.translate(reply, conversation.language)
    return use_translation(translated) if translated.present? && translated != reply

    message.translation_failed = true
  end

  def use_translation(translated)
    message.translations = { original_language => original_text }
    message.source_language = conversation.language
    message.translation_provider = translator.provider
    message.content = with_quoted_history(translated)
    message.content_attributes['email'] = email_content(message.content) if email_reply?
  end

  def translator
    @translator ||= Captain::Conversation::TranslatorService.new(account: account, conversation_display_id: conversation.display_id)
  end

  def reply_language
    @reply_language ||= translator.language(reply)
  end

  def original_language
    reply_language || agent_locale || account.locale
  end

  def agent_locale
    message.sender.ui_settings['locale'].presence if message.sender.is_a?(User)
  end

  def reply
    @reply ||= quoted_history.blank? ? message.content : message.content.delete_suffix(quoted_history).strip
  end

  def quoted_history
    @quoted_history ||= inbox.email? ? message.content[/^>.*\z/m].to_s : ''
  end

  def with_quoted_history(translated)
    quoted_history.blank? ? translated : "#{translated.strip}\n\n#{quoted_history}"
  end

  def email_reply?
    inbox.email? && message.content_attributes['email'].present?
  end

  def original_text
    email_reply? ? String.new(render_email_html(normalize_email_body(message.content))) : message.content
  end

  def email_content(content)
    text = normalize_email_body(content)
    html = render_email_html(text)
    message.content_attributes['email'].merge(
      'html_content' => { 'full' => html, 'reply' => html }, 'text_content' => { 'full' => text, 'reply' => text }
    )
  end
end
