# Create, edit, delete and read the message templates of a WhatsApp Cloud inbox in Meta, from the templates page.
# Administrators only: agents use the templates, they do not manage them (see InboxPolicy#manage_whatsapp_templates?).
class Api::V1::Accounts::InboxWhatsappTemplatesController < Api::V1::Accounts::BaseController
  LANGUAGE_FORMAT = /\A[a-z]{2,3}(_[A-Z]{2})?\z/
  META_ERROR_STATUS = { 'not_found' => :not_found, 'rate_limited' => :bad_gateway, 'meta_unreachable' => :bad_gateway }.freeze

  before_action :fetch_inbox
  before_action :validate_whatsapp_cloud_channel

  # The live state of one template (status, rejection reason, quality).
  def show
    render json: management_service.fetch(params[:id])
  rescue Whatsapp::TemplateManagementService::Error => e
    render_meta_error(e)
  end

  # What the form may offer for this channel: media headers need the app behind the channel token.
  def capabilities
    available = header_handle_service.available?
    render json: { media_header: available, reason: available ? nil : header_handle_service.unavailable_reason }
  end

  # Meta's Template Library, searchable (search, language, topic, usecase, industry) and paginated (after).
  def library
    render json: management_service.library(**library_filters)
  rescue Whatsapp::TemplateManagementService::Error => e
    render_meta_error(e)
  end

  # Creates a template from the library: the text is Meta's, the admin only chooses the name, language and the
  # values its buttons ask for.
  def create_from_library
    attributes = library_template_params
    return render_error('library_name_required') if attributes[:library_template_name].blank?
    return render_error('invalid_name') unless Whatsapp::TemplateComponentsBuilder.valid_name?(attributes[:name])
    return render_error('invalid_language') unless attributes[:language].to_s.match?(LANGUAGE_FORMAT)
    return render_error('invalid_category') unless Whatsapp::TemplateComponentsBuilder::CATEGORIES.include?(attributes[:category])

    render json: management_service.create_from_library(**attributes.to_h.symbolize_keys), status: :created
  rescue Whatsapp::TemplateManagementService::Error => e
    render_meta_error(e)
  end

  def create
    return render_error('invalid_name') unless Whatsapp::TemplateComponentsBuilder.valid_name?(template_params[:name])
    return render_error('invalid_language') unless template_params[:language].to_s.match?(LANGUAGE_FORMAT)
    return render_error('invalid_category') unless Whatsapp::TemplateComponentsBuilder::CATEGORIES.include?(template_params[:category])

    created = management_service.create(
      name: template_params[:name], language: template_params[:language], category: template_params[:category],
      components: components_builder.components, parameter_format: components_builder.parameter_format
    )
    render json: created, status: :created
  rescue Whatsapp::TemplateComponentsBuilder::Invalid => e
    render_invalid(e)
  rescue Whatsapp::TemplateManagementService::Error => e
    render_meta_error(e)
  end

  # An edit sends the components again (Meta replaces them) and, for a template that is not approved, the category.
  def update
    category = template_params[:category]
    return render_error('invalid_category') if category.present? && Whatsapp::TemplateComponentsBuilder::CATEGORIES.exclude?(category)

    render json: management_service.update(params[:id], components: components_builder.components, category: category)
  rescue Whatsapp::TemplateComponentsBuilder::Invalid => e
    render_invalid(e)
  rescue Whatsapp::TemplateManagementService::Error => e
    render_meta_error(e)
  end

  # Deletes one template: the id is the hsm_id, so the other languages of the same name stay.
  def destroy
    return render_error('name_required') if params[:name].blank?

    render json: management_service.delete(name: params[:name], hsm_id: params[:id])
  rescue Whatsapp::TemplateManagementService::Error => e
    render_meta_error(e)
  end

  # The example file of a media header, uploaded to Meta's Resumable Upload API. Returns the handle the template needs.
  def header_handle
    file = params[:file]
    return render_error('file_required') unless file.respond_to?(:tempfile)

    format = params.require(:header_format)
    Whatsapp::TemplateHeaderMedia.validate!(format, Marcel::MimeType.for(file.tempfile, name: file.original_filename), file.size)
    render json: { handle: header_handle_service.upload!(file), format: format.to_s.upcase, name: file.original_filename }, status: :created
  rescue ActionController::ParameterMissing
    render_error('file_required')
  rescue Whatsapp::TemplateHeaderMedia::InvalidFile => e
    render_error(e.reason == 'invalid_format' ? 'invalid_header_format' : "file_#{e.reason}", status: :unprocessable_entity)
  rescue Whatsapp::TemplateHeaderHandleService::Error => e
    render_error(e.message, status: e.message == 'media_header_unavailable' ? :unprocessable_entity : :bad_gateway)
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :manage_whatsapp_templates?
  end

  def validate_whatsapp_cloud_channel
    return if @inbox.whatsapp? && @inbox.channel.try(:provider) == 'whatsapp_cloud'

    render_error('cloud_channel_required', status: :unprocessable_entity)
  end

  def management_service
    @management_service ||= Whatsapp::TemplateManagementService.new(@inbox.channel)
  end

  def header_handle_service
    @header_handle_service ||= Whatsapp::TemplateHeaderHandleService.new(@inbox.channel)
  end

  def template_params
    @template_params ||= params.fetch(:template, {}).permit(
      :name, :language, :category,
      header: [:format, :text, :handle, { examples: [] }],
      body: [:text, { examples: [] }],
      footer: [:text],
      buttons: [:type, :text, :url, :phone_number, :code, { examples: [] }]
    )
  end

  def library_filters
    params.permit(:search, :language, :topic, :usecase, :industry, :after).to_h.symbolize_keys
  end

  def library_template_params
    params.require(:library_template).permit(
      :library_template_name, :name, :language, :category, button_inputs: [:type, :phone_number, { url: [:base_url, :url_suffix_example] }]
    )
  end

  def components_builder
    @components_builder ||= Whatsapp::TemplateComponentsBuilder.new(
      header: template_params[:header], body: template_params[:body], footer: template_params[:footer], buttons: template_params[:buttons],
      category: template_params[:category], preserved: preserved_params
    )
  end

  # The components and buttons the form cannot express, returned as they came from Meta and sent back untouched.
  def preserved_params
    preserved = params.dig(:template, :preserved)
    preserved.respond_to?(:to_unsafe_h) ? preserved.to_unsafe_h : {}
  end

  def render_invalid(error)
    render json: { error: error.code, message: translate_error(error.code, error.details), details: error.details }, status: :unprocessable_entity
  end

  def render_meta_error(error)
    status = META_ERROR_STATUS.fetch(error.code, :unprocessable_entity)
    render json: { error: error.code, message: translate_error(error.code, detail: error.detail), meta_code: error.meta_code }, status: status
  end

  def render_error(code, status: :unprocessable_entity)
    render json: { error: code, message: translate_error(code) }, status: status
  end

  def translate_error(code, options = {})
    I18n.t("whatsapp_templates.errors.#{code}", **options.symbolize_keys, default: I18n.t('whatsapp_templates.errors.unknown'))
  end
end
