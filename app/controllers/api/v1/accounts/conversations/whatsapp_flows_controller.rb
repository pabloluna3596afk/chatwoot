class Api::V1::Accounts::Conversations::WhatsappFlowsController < Api::V1::Accounts::Conversations::BaseController
  rescue_from Whatsapp::Flows::SendFlowService::Error do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    eligible_ids = Whatsapp::Flows::SendFlowService.new(conversation: @conversation, sender: Current.user).eligible_flows.ids
    waba_id = @conversation.inbox.channel.provider_config.fetch('business_account_id')
    can_reply = @conversation.can_reply?
    flows = @conversation.account.whatsapp_flows.includes(:whatsapp_flow_publications).order(:name)
    payload = flows.map do |flow|
      publication = flow.whatsapp_flow_publications.find { |item| item.waba_id == waba_id }
      flow.slice(:id, :name, :categories).merge(
        status: publication&.status || 'none',
        unpublished_changes: publication&.published_at.present? && publication.published_at < flow.updated_at,
        screens: flow.definition.fetch('screens').size,
        can_send: can_reply && eligible_ids.include?(flow.id)
      )
    end
    render json: { payload: payload, can_reply: can_reply }
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
