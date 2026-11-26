class Api::V1::Accounts::Integrations::CalendarTemplateDraftsController < Api::V1::Accounts::Integrations::BaseController
  before_action :check_admin_authorization?

  rescue_from Whatsapp::TemplateComponentsBuilder::Invalid do |error|
    render json: { error: error.code }, status: :unprocessable_entity
  end

  def show
    render json: Calendar::TemplateDrafts::Provisioner.new(account: Current.account).status
  end

  def create
    if params.key?(:language) && !Calendar::TemplateDefinitions::TEMPLATES.key?(params[:language])
      raise Whatsapp::TemplateComponentsBuilder::Invalid, 'language'
    end

    render json: Calendar::TemplateDrafts::Provisioner.new(account: Current.account).perform(language: params[:language])
  end

  def submit
    return invalid_submission_input unless submission_input_valid?

    submissions = Calendar::TemplateDrafts::Submitter.new(account: Current.account, actor: Current.user,
                                                            functions: params[:functions], waba_ids: params[:waba_ids]).perform
    render json: { submissions: submissions.map { |submission| submission.attributes.slice(*WhatsappTemplateDraftSerializer::SUBMISSION_FIELDS) } },
           status: :accepted
  end

  def link
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'invalid_input' unless valid_link_input?

    render json: Calendar::TemplateDrafts::Linker.new(account: Current.account, function: params[:function], channel_id: params[:channel_id])
                                                 .perform(**params.permit(:draft_id, :template_name, :remote_template_id).to_h.symbolize_keys)
  end

  private

  def valid_link_input?
    Calendar::TemplateDefinitions::FUNCTIONS.key?(params[:function]) && params[:channel_id].is_a?(Integer) && valid_selection?
  end

  def valid_selection?
    if params.key?(:draft_id)
      params[:draft_id].is_a?(Integer) && !params.key?(:template_name) && !params.key?(:remote_template_id)
    else
      [:template_name, :remote_template_id].all? { |key| params[key].is_a?(String) && params[key].present? }
    end
  end

  def submission_input_valid?
    functions = params[:functions]
    waba_ids = params[:waba_ids]
    return false unless functions.is_a?(Array) && functions.present? && functions.all? { |value| value.is_a?(String) }
    return false unless functions.uniq == functions && (functions - Calendar::TemplateDefinitions::FUNCTIONS.keys).empty?
    return false unless waba_ids.is_a?(Array) && waba_ids.present? && waba_ids.all? { |value| value.is_a?(String) && value.present? }
    return false unless waba_ids.uniq == waba_ids

    available = Current.account.whatsapp_channels.where(provider: 'whatsapp_cloud')
                       .pluck(Arel.sql("provider_config ->> 'business_account_id'")).compact.uniq
    (waba_ids - available).empty?
  end

  def invalid_submission_input
    render json: { error: 'invalid_submission' }, status: :unprocessable_entity
  end
end
