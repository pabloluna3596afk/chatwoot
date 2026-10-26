class Captain::Conversation::ContactMessageTranslationJob < ApplicationJob
  queue_as :default

  def perform(message, target_language)
    Captain::Conversation::ContactMessageTranslationService.new(message: message, target_language: target_language).perform
  rescue StandardError
    message.with_lock do
      next if message.deleted

      message.translation_failed = true
      message.content_attributes['translation_status'] = 'failed'
      message.save!
    end
    raise
  end
end
