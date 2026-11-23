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
end
