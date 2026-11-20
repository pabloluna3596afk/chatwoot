class Api::V1::Accounts::Conversations::CaptainDecisionsController < Api::V1::Accounts::Conversations::BaseController
  before_action :require_human_member
  before_action :validate_lookup_id

  def index
    message = @conversation.messages.find(params[:message_id])
    return head :unauthorized unless Captain::Decisions::Access.visible_anchor?(Current.user, message)

    decisions = decision_scope.where(anchor_message_id: message.id).order(:occurred_at, :id)
    render json: decisions.map { |decision| Captain::DecisionSerializer.new(decision, pundit_user).as_json }
  end

  def show
    decision = decision_scope.find(params[:id])
    return head :not_found unless decision.anchor_message
    return head :unauthorized unless Captain::Decisions::Access.visible_anchor?(Current.user, decision.anchor_message)

    render json: Captain::DecisionSerializer.new(decision, pundit_user).as_json
  end

  private

  def require_human_member
    head :unauthorized unless Current.user.is_a?(User) && Current.account_user
  end

  def validate_lookup_id
    key = action_name == 'index' ? :message_id : :id
    return if params[key].is_a?(String) && params[key].match?(/\A[1-9][0-9]*\z/)

    render json: { error: "#{key} must be a positive integer" }, status: :unprocessable_entity
  end

  def decision_scope
    Current.account.captain_decisions.where(conversation_id: @conversation.id).includes(:assistant, :anchor_message, :agent_session)
  end
end
