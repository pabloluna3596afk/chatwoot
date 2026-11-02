class Captain::Copilot::ResponseJob < ApplicationJob
  queue_as :default

  def perform(assistant:, conversation_id:, user_id:, copilot_thread_id:, message:)
    Rails.logger.info("#{self.class.name} Copilot response job for assistant_id=#{assistant.id} user_id=#{user_id}")
    generate_chat_response(
      assistant: assistant,
      conversation_id: conversation_id,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      message: message
    )
  rescue StandardError => e
    record_failure(assistant: assistant, user_id: user_id, copilot_thread_id: copilot_thread_id, error: e)
  end

  private

  def record_failure(assistant:, user_id:, copilot_thread_id:, error:)
    Rails.logger.error("#{self.class.name} failed error=#{error.class} assistant_id=#{assistant.id} user_id=#{user_id} " \
                       "copilot_thread_id=#{copilot_thread_id}")
    return if copilot_thread_id.blank?

    thread = CopilotThread.find_by(id: copilot_thread_id, account_id: assistant.account_id)
    thread&.copilot_messages&.create!(
      message_type: :assistant,
      message: {
        content: I18n.with_locale(assistant.account.locale) { I18n.t('captain.copilot_response_failed') },
        error: true
      }
    )
  end

  def generate_chat_response(assistant:, conversation_id:, user_id:, copilot_thread_id:, message:)
    service = Captain::Copilot::ChatService.new(
      assistant,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      conversation_id: conversation_id
    )
    # When using copilot_thread, message is already in previous_history
    # Pass nil to avoid duplicate
    service.generate_response(copilot_thread_id.present? ? nil : message)
  end
end
