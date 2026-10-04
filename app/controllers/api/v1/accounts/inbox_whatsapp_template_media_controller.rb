# The file of a template header (image, video or document), uploaded once to Meta's media endpoint when the template
# is picked. Returns the header params to keep with the template (see Whatsapp::TemplateHeaderMedia).
class Api::V1::Accounts::InboxWhatsappTemplateMediaController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :validate_whatsapp_cloud_channel

  def create
    file = params.require(:file)
    return render_error('file_required') unless file.respond_to?(:tempfile)

    header = Whatsapp::TemplateHeaderMedia.store_and_upload!(@inbox.channel, format: params.require(:header_format), file: file)
    render json: header, status: :created
  rescue ActionController::ParameterMissing
    render_error('file_required')
  rescue Whatsapp::TemplateHeaderMedia::InvalidFile => e
    render_error(e.reason, e.message)
  rescue Whatsapp::MediaUploadService::UploadError => e
    render_error('upload_failed', e.message, :bad_gateway)
  end

  private

  def render_error(reason, message = reason, status = :unprocessable_entity)
    render json: { error: reason, message: message }, status: status
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def validate_whatsapp_cloud_channel
    return if @inbox.whatsapp? && @inbox.channel.try(:provider) == 'whatsapp_cloud'

    render json: { error: 'WhatsApp Cloud channel required' }, status: :bad_request
  end
end
