module Enterprise::Api::V1::Accounts::Conversations::MessagesController
  def destroy
    audited_message = message
    # Lock before the deleted check so concurrent deletes cannot both write an audit entry.
    audited_message.with_lock do
      next super if audited_message.deleted

      audit_context = message_deletion_audit_context(audited_message)
      super
      create_message_deletion_audit_log(audited_message, audit_context)
    end
  end

  MAX_AUTO_TRANSLATE_MESSAGES = 20

  def auto_translate
    return head :forbidden unless Current.account.auto_translate_enabled?

    message_ids = params.require(:message_ids)
    unless valid_message_ids?(message_ids)
      return render json: { error: I18n.t('errors.auto_translate.invalid_messages') }, status: :unprocessable_entity
    end

    @conversation.messages.where(id: message_ids).find_each do |contact_message|
      next unless translatable_contact_message?(contact_message)

      Captain::Conversation::ContactMessageTranslationJob.perform_later(contact_message, agent_language)
    end
    head :accepted
  end

  private

  # Snapshot the context before super soft-deletes the message.
  def message_deletion_audit_context(deleted_message)
    {
      'content' => deleted_message.content,
      'conversation_id' => deleted_message.conversation_id,
      'display_id' => deleted_message.conversation.display_id,
      'inbox_id' => deleted_message.inbox_id,
      'sender_type' => deleted_message.sender_type,
      'sender_id' => deleted_message.sender_id
    }
  end

  def create_message_deletion_audit_log(deleted_message, audit_context)
    Enterprise::AuditLog.create!(
      auditable: deleted_message,
      action: 'destroy',
      user: Current.user,
      associated: deleted_message.account,
      remote_address: request.remote_ip,
      audited_changes: audit_context
    )
  end

  def valid_message_ids?(message_ids)
    message_ids.is_a?(Array) && message_ids.size <= MAX_AUTO_TRANSLATE_MESSAGES &&
      message_ids.uniq.size == message_ids.size && @conversation.messages.where(id: message_ids).count == message_ids.size
  end

  def translatable_contact_message?(message)
    message.incoming? && !message.private? && message.text? && message.content.present?
  end

  def agent_language
    Current.user.ui_settings['locale'].presence || Current.account.locale
  end
end
