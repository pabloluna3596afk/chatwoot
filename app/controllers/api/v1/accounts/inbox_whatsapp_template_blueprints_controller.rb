class Api::V1::Accounts::InboxWhatsappTemplateBlueprintsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :validate_whatsapp_cloud_channel

  def create
    result = Whatsapp::BotTemplateBlueprintService.new(@inbox.channel).submit(params.require(:blueprint_id))
    if result[:success]
      render json: {
        template: {
          name: result[:template_name],
          template_id: result[:template_id],
          status: result[:status],
          language: result[:language]
        }
      }, status: :created
    else
      render json: { error: result[:error], details: result[:response_body] }, status: :unprocessable_entity
    end
  rescue ActionController::ParameterMissing
    render json: { error: 'blueprint_id is required' }, status: :unprocessable_entity
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def validate_whatsapp_cloud_channel
    return if @inbox.whatsapp? && @inbox.channel.try(:provider) == 'whatsapp_cloud'

    render json: { error: 'WhatsApp Cloud channel required' }, status: :bad_request
  end
end
