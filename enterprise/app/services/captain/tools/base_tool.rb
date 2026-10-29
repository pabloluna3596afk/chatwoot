class Captain::Tools::BaseTool < RubyLLM::Tool
  attr_accessor :assistant, :copilot_tool_call_limiter

  def self.inherited(subclass)
    super
    subclass.prepend(Captain::Tools::Instrumentation)
  end

  def initialize(assistant, user: nil)
    @assistant = assistant
    @user = user
    super()
  end

  def parameters_schema
    schema = super
    return schema unless self.class.name.start_with?('Captain::Tools::Copilot::') ||
                         instance_of?(Captain::Tools::SearchDocumentationService)

    schema.merge('additionalProperties' => false)
  end

  def active?
    true
  end

  private

  def user_has_permission(permission)
    return false if @user.blank?

    account_user = AccountUser.find_by(account_id: @assistant.account_id, user_id: @user.id)
    return false if account_user.blank?

    return account_user.custom_role.permissions.include?(permission) if account_user.custom_role.present?

    account_user.administrator? || account_user.agent?
  end
end
