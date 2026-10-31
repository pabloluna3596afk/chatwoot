class Captain::Copilot::Actions::PrivateNote < Captain::Copilot::Actions::Base
  def self.action_name = 'private_note'

  def self.schema
    { type: 'object', description: 'Create a private note on a conversation.',
      examples: [{ content: 'Please follow up tomorrow.' }], required: %w[content], additionalProperties: false,
      properties: { content: { type: 'string' } } }
  end

  def required_permission = 'conversation_manage'

  def validate
    raise ArgumentError, 'Private notes require a conversation target' unless @target_type == 'Conversation'

    super
  end

  def validate_payload!
    validate_payload_keys!(%w[content], 'Pass the note text in content.')
    content = @payload['content']
    raise ArgumentError, 'Note content is required' unless content.is_a?(String) && content.present?
  end

  def execute
    message = Messages::MessageBuilder.new(@user, target, ActionController::Parameters.new(content: @payload.fetch('content'), private: true)).perform
    raise StandardError, 'Could not save private note' if message.blank? || !message.private?

    { code: 'private_note_added', message_id: message.id }
  end
end
