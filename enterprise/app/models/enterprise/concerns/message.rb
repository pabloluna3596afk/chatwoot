module Enterprise::Concerns::Message
  extend ActiveSupport::Concern

  included do
    has_one :call, dependent: :nullify
    has_many :message_reports, class_name: 'Captain::MessageReport', dependent: :destroy_async

    before_create :mark_for_translation, if: :translation_enabled?
  end

  private

  def mark_for_translation
    content_attributes['translation_pending'] = true
  end

  def translation_enabled?
    return false unless account.auto_translate_enabled? && content.present? && !private?
    return false if additional_attributes.to_h['customer_reminder'].present?

    template? ? email_template_message? : translatable_agent_reply?
  end

  def email_template_message?
    inbox.email?
  end

  def translatable_agent_reply?
    outgoing? && sender.is_a?(User) && text? && !forwarded_message? && !whatsapp_template?
  end

  def forwarded_message?
    content_attributes['forwarded_message_id'].present?
  end

  def whatsapp_template?
    additional_attributes.to_h['template_params'].present?
  end
end
