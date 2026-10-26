require 'google/cloud/translate/v3'

class Integrations::GoogleTranslate::ProcessorService
  pattr_initialize [:message, :target_language, { hook: nil }]

  def perform
    return if resolved_hook.blank?

    content = translation_content
    return if content.blank?

    response = client.translate_text(
      contents: [content],
      target_language_code: target_language.tr('_', '-'),
      parent: parent,
      mime_type: mime_type
    )

    return if response.translations.first.blank?

    response.translations.first.translated_text
  end

  def translate(text, language, mime_type: 'text/plain')
    return if resolved_hook.blank?

    response = client.translate_text(contents: [text], target_language_code: language.tr('_', '-'), parent: parent,
                                     mime_type: mime_type)
    response.translations.first&.translated_text
  end

  def detect(text)
    return if resolved_hook.blank?

    code = client.detect_language(content: text[0...1500], parent: parent).languages.first&.language_code
    code unless code.blank? || code == 'und'
  end

  private

  def email_channel?
    message&.inbox&.email?
  end

  def email_content
    @email_content ||= {
      html: message.content_attributes.dig('email', 'html_content', 'full'),
      text: message.content_attributes.dig('email', 'text_content', 'full'),
      content_type: message.content_attributes.dig('email', 'content_type')
    }
  end

  def html_content_available?
    email_content[:html].present?
  end

  def plain_text_content_available?
    email_content[:content_type]&.include?('text/plain') &&
      email_content[:text].present?
  end

  def translation_content
    return message.content unless email_channel?
    return email_content[:html] if html_content_available?
    return email_content[:text] if plain_text_content_available?

    message.content
  end

  def mime_type
    if email_channel? && html_content_available?
      'text/html'
    else
      'text/plain'
    end
  end

  def resolved_hook
    @resolved_hook ||= hook || message&.account&.hooks&.find_by(app_id: 'google_translate')
  end

  def parent
    "projects/#{resolved_hook.settings['project_id']}"
  end

  def client
    @client ||= ::Google::Cloud::Translate::V3::TranslationService::Client.new do |config|
      config.credentials = credentials
    end
  end

  def credentials
    resolved_hook.google_translate_credentials
  end
end
