class Api::V1::Accounts::Conversations::WhatsappFlowsController < Api::V1::Accounts::Conversations::BaseController
  rescue_from Whatsapp::Flows::SendFlowService::Error do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    flows = Whatsapp::Flows::SendFlowService.new(conversation: @conversation, sender: Current.user).eligible_flows
    render json: { payload: flows.map { |flow| flow.slice(:id, :name) }, can_reply: @conversation.can_reply? }
  end

  def create
    Whatsapp::Flows::SendFlowService::TEXT_LIMITS.each_key do |key|
      raise Whatsapp::Flows::SendFlowService::Error, "Invalid #{key}" if params.key?(key) && !params[key].is_a?(String)
    end
    @message = Whatsapp::Flows::SendFlowService.new(
      conversation: @conversation, sender: Current.user, params: params.permit(:whatsapp_flow_id, :header, :body, :cta).to_h
    ).perform
    render 'api/v1/accounts/conversations/messages/create'
  end
end
