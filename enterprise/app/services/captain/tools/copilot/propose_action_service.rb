class Captain::Tools::Copilot::ProposeActionService < Captain::Tools::BaseTool
  def initialize(assistant, copilot_thread:, user: nil)
    @copilot_thread = copilot_thread
    @propose_action_calls = 0
    super(assistant, user: user)
  end

  def self.name = 'propose_action'

  description 'Create a proposal for the user to review. This tool never executes the action.'
  parameters type: 'object', required: %w[action target payload], additionalProperties: false,
             properties: {
               action: { type: 'string', enum: Captain::Copilot::ActionRegistry.all.map(&:action_name) },
               target: {
                 type: 'object', required: %w[type id], additionalProperties: false,
                 properties: {
                   type: { type: 'string', enum: %w[Conversation Contact] },
                   id: { type: 'integer' }
                 }
               },
               payload: { type: 'object', description: 'Action-specific values to show and validate before approval' }
             }

  def execute(action:, target:, payload:)
    @propose_action_calls += 1
    if @propose_action_calls > Captain::Copilot::ActionItemService::MAX_PROPOSALS_PER_TURN
      raise ArgumentError, 'At most three proposals are allowed per turn'
    end

    raise ArgumentError, 'Target must be an object' unless target.is_a?(Hash)
    raise ArgumentError, 'Target only accepts type and id' if (target.keys.map(&:to_s) - %w[type id]).any?

    item = Captain::Copilot::ActionItemService.new(thread: @copilot_thread, user: @user).propose(
      action_name: action, target_type: target.fetch('type'), target_id: target.fetch('id'),
      payload: payload, turn_count: @propose_action_calls
    )
    { status: item.status, message: 'Proposal created and waiting for user approval' }
  rescue ArgumentError, KeyError, ActiveRecord::RecordNotFound => e
    { error: e.message }
  end

  def active?
    @copilot_thread.present? && @user.present? &&
      (user_has_permission('conversation_manage') || user_has_permission('conversation_unassigned_manage') ||
       user_has_permission('conversation_participating_manage') || user_has_permission('contact_manage'))
  end
end
