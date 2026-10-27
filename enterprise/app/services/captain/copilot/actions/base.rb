class Captain::Copilot::Actions::Base
  def self.action_name = name.demodulize.underscore
  def self.schema = { type: 'object', additionalProperties: false }

  def initialize(account:, user:, target_type:, target_id:, payload:)
    @account = account
    @user = user
    @target_type = target_type
    @target_id = target_id
    raise ArgumentError, 'Payload must be an object' unless payload.is_a?(Hash)
    raise ArgumentError, 'Target id must be an integer' unless target_id.is_a?(Integer)

    @payload = payload.deep_stringify_keys
  end

  def validate
    raise ArgumentError, 'Target must be a conversation or contact' unless %w[Conversation Contact].include?(@target_type)

    target || raise(ActiveRecord::RecordNotFound, 'Target not found')
    authorize!
    validate_payload!
  end

  def preview = { action: self.class.action_name, target_type: @target_type, target_id: @target_id, payload: @payload }

  def required_permission
    @target_type == 'Contact' ? 'contact_manage' : 'conversation_manage'
  end

  private

  def target
    @target ||= if @target_type == 'Conversation'
                  @account.conversations.find_by(display_id: @target_id)
                else
                  @account.contacts.find_by(id: @target_id)
                end
  end

  def authorize!
    account_user = @account.account_users.find_by(user_id: @user.id)
    raise ArgumentError, 'User is not part of this account' if account_user.blank?

    raise ArgumentError, 'You do not have permission to update this target' unless authorized_user?(account_user)
    raise ActiveRecord::RecordNotFound, 'Conversation not found' if inaccessible_conversation?
  end

  def authorized_user?(account_user)
    return account_user.administrator? || account_user.agent? if account_user.custom_role.blank?

    permissions = account_user.custom_role.permissions
    return permissions.include?('contact_manage') if @target_type == 'Contact'

    permissions.intersect?(%w[conversation_manage conversation_unassigned_manage conversation_participating_manage])
  end

  def inaccessible_conversation?
    @target_type == 'Conversation' && !accessible_conversation?
  end

  def accessible_conversation?
    access = Object.new.extend(Captain::Copilot::ConversationAccess)
    access.send(:accessible_conversation, account: @account, user: @user, display_id: target.display_id).present?
  end

  def validate_payload!
    raise NotImplementedError
  end

  def validate_payload_keys!(allowed_keys)
    raise ArgumentError, 'Payload contains unsupported fields' if (@payload.keys - allowed_keys).any?
  end
end
