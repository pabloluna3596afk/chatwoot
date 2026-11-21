class Api::V1::Accounts::WhatsappTemplateDraftsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :fetch_draft, except: [:index, :create, :new_version]
  before_action :validate_input, only: [:create, :update]
  before_action :validate_pagination, only: :index
  before_action :validate_revision, only: [:update, :archive, :destroy, :remove_media, :submit]

  rescue_from Whatsapp::TemplateComponentsBuilder::Invalid do |error|
    message = I18n.t("whatsapp_templates.errors.#{error.code}", **error.details, default: I18n.t('whatsapp_templates.errors.unknown'))
    render json: { error: error.code, message: message, details: error.details }, status: :unprocessable_entity
  end
  rescue_from Whatsapp::TemplateHeaderMedia::InvalidFile do |error|
    render json: { error: "file_#{error.reason}" }, status: :unprocessable_entity
  end

  rescue_from ActiveRecord::StaleObjectError do
    render json: { error: 'stale_revision', message: 'El borrador cambió. Recarga antes de guardar.' }, status: :conflict
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: 'invalid_draft', details: error.record.errors.to_hash }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: 'identity_conflict', message: 'Ya existe un borrador o envío con ese destino, nombre e idioma.' }, status: :conflict
  end

  def index
    drafts = Current.account.whatsapp_template_drafts.active.order(updated_at: :desc, id: :desc)
    page = params.fetch(:page, '1').to_i
    per_page = params.fetch(:per_page, '20').to_i
    rows = drafts.includes(:submissions, media_attachment: :blob).offset((page - 1) * per_page).limit(per_page)
    render json: { payload: rows.map { |draft| WhatsappTemplateDraftSerializer.render(draft) },
                   meta: { total_count: drafts.count, current_page: page, per_page: per_page } }
  end

  def show
    render_draft(@draft)
  end

  def submit
    submission = Whatsapp::SubmitTemplateDraftService.new(@draft, Current.user, expected_revision).perform
    render json: submission.attributes.slice(*WhatsappTemplateDraftSerializer::SUBMISSION_FIELDS), status: :accepted
  end

  def reconcile
    submission = @draft.submissions.find(params[:submission_id])
    Whatsapp::SubmitTemplateDraftJob.perform_later(submission.id, refresh: true)
    render json: submission.attributes.slice(*WhatsappTemplateDraftSerializer::SUBMISSION_FIELDS), status: :accepted
  end

  def create
    draft = Current.account.whatsapp_template_drafts.new(draft_attributes.merge(created_by: Current.user, updated_by: Current.user))
    draft.save!
    render_draft(draft, :created)
  end

  def update
    @draft.update!(draft_attributes.merge(updated_by: Current.user))
    render_draft(@draft)
  end

  def archive
    @draft.update!(lock_version: expected_revision, archived_at: Time.current, updated_by: Current.user)
    render_draft(@draft)
  end

  def destroy
    @draft.with_lock do
      raise ActiveRecord::StaleObjectError.new(@draft, 'destroy') unless @draft.lock_version == expected_revision

      if @draft.submissions.exists? || @draft.class.exists?(source_draft_id: @draft.id)
        @draft.update!(archived_at: Time.current, updated_by: Current.user)
      else
        @draft.destroy!
      end
    end
    head :no_content
  end

  def duplicate
    return invalid_input unless params[:destination].is_a?(ActionController::Parameters)

    destination = params[:destination].permit(:preferred_channel_id, :waba_id).to_h
    return invalid_input unless Whatsapp::TemplateDraftInput.destination?(destination)

    copy = Whatsapp::TemplateDraftCopyService.new(Current.account, Current.user).duplicate(@draft, destination)
    render_draft(copy, :created)
  end

  def new_version
    return invalid_input unless params[:channel_id].is_a?(Integer) && params[:remote_id].is_a?(String)

    channel = Current.account.whatsapp_channels.find(params[:channel_id])
    authorize channel.inbox, :manage_whatsapp_templates?
    return invalid_input unless channel.provider == 'whatsapp_cloud'

    draft = Whatsapp::TemplateDraftCopyService.new(Current.account, Current.user).from_remote(channel, params[:remote_id])
    render_draft(draft, :created)
  end

  def download_media
    raise ActiveRecord::RecordNotFound unless @draft.media.attached?

    send_data @draft.media.download, filename: @draft.media.filename.to_s, type: @draft.media.content_type, disposition: 'attachment'
  end

  # Multipart encodes the revision as a decimal string; JSON edit endpoints require an integer.
  def upload_media
    valid_revision = params[:lock_version].is_a?(String) && params[:lock_version].match?(/\A(?:0|[1-9]\d*)\z/)
    return invalid_input unless valid_revision && params[:file].is_a?(ActionDispatch::Http::UploadedFile)

    @draft.with_lock do
      raise ActiveRecord::StaleObjectError.new(@draft, 'update') unless @draft.lock_version == params[:lock_version].to_i

      @draft.assign_attributes(media: params[:file], updated_by: Current.user, updated_at: Time.current)
      @draft.save!
    end
    render_draft(@draft)
  end

  def remove_media
    @draft.update!(lock_version: expected_revision, media: nil, updated_by: Current.user, updated_at: Time.current)
    render_draft(@draft)
  end

  private

  def fetch_draft
    @draft = Current.account.whatsapp_template_drafts.find(params[:id])
  end

  def render_draft(draft, status = :ok)
    render json: WhatsappTemplateDraftSerializer.render(draft), status: status
  end

  def expected_revision
    params[:lock_version] || params.dig(:draft, :lock_version)
  end

  def validate_revision
    invalid_input unless expected_revision.is_a?(Integer) && expected_revision >= 0
  end

  def draft_attributes
    attributes = params[:draft].permit(:title, :name, :language, :category, :parameter_format, :waba_id, :preferred_channel_id).to_h
    attributes[:lock_version] = expected_revision if action_name == 'update'
    [:definition, :variable_bindings].each do |field|
      attributes[field] = params[:draft][field].to_unsafe_h if params[:draft].key?(field)
    end
    attributes
  end

  def validate_input
    raw = params[:draft]
    invalid_input unless Whatsapp::TemplateDraftInput.valid?(raw)
  end

  def invalid_input
    render json: { error: 'invalid_draft', message: 'El borrador tiene campos con un tipo o formato incorrecto.' }, status: :unprocessable_entity
  end

  def validate_pagination
    [:page, :per_page].each do |key|
      value = params.fetch(key, '1')
      return invalid_input unless value.is_a?(String) && value.match?(/\A[1-9]\d{0,8}\z/)
    end
    invalid_input if params.fetch(:per_page, '20').to_i > 100
  end
end
