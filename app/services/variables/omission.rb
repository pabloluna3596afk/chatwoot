class Variables::Omission
  def self.create_note(conversation:, surface:, error:)
    content = I18n.t('variables.delivery_skipped', locale: conversation.account.locale, surface: surface, reason: error.message)
    message = conversation.messages.build(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :outgoing, private: true, content: content
    )
    message.variables_resolved!
    message.save!
  end
end
