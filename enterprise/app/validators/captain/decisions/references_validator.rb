class Captain::Decisions::ReferencesValidator < ActiveModel::Validator
  def validate(record)
    validate_accounts(record)
    validate_conversations(record)
    validate_assistants(record)
    validate_session(record) if record.agent_session
  end

  private

  def validate_accounts(record)
    %i[conversation assistant anchor_message agent_session parent_decision].each do |name|
      reference = record.public_send(name)
      record.errors.add(name, 'must belong to the decision account') if reference && reference.account_id != record.account_id
    end
  end

  def validate_conversations(record)
    %i[anchor_message parent_decision].each do |name|
      reference = record.public_send(name)
      next unless reference && reference.conversation_id != record.conversation_id

      record.errors.add(name, 'must belong to the decision conversation')
    end
  end

  def validate_assistants(record)
    parent = record.parent_decision
    record.errors.add(:parent_decision, 'must use the same assistant') if parent && parent.assistant_id != record.assistant_id
    anchor = record.anchor_message
    return unless anchor&.sender_type == 'Captain::Assistant' && anchor.sender_id != record.assistant_id

    record.errors.add(:anchor_message, 'must use the same assistant')
  end

  def validate_session(record)
    session = record.agent_session
    unless session.session_assistant? && session.subject_type == 'Conversation' && session.subject_id == record.conversation_id
      record.errors.add(:agent_session, 'must describe this conversation')
    end
    record.errors.add(:agent_session, 'must use the same assistant') if session.assistant_id != record.assistant_id
    validate_session_anchor(record, session)
  end

  def validate_session_anchor(record, session)
    return unless record.anchor_message_id
    return if session.result_type == 'Message' && session.result_id == record.anchor_message_id

    record.errors.add(:agent_session, 'must describe the anchor message')
  end
end
