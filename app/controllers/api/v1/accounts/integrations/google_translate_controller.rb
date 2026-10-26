class Api::V1::Accounts::Integrations::GoogleTranslateController < Api::V1::Accounts::Integrations::BaseController
  before_action :check_authorization

  def create
    @hook = Current.account.hooks.find_or_initialize_by(app_id: 'google_translate')
    @hook.assign_attributes(
      settings: { 'project_id' => permitted_params[:project_id] },
      access_token: permitted_params[:credentials].to_json,
      status: 'enabled'
    )

    unless Integrations::GoogleTranslate::CredentialsValidator.valid?(@hook)
      return render json: { error: I18n.t('errors.google_translate.invalid_credentials') }, status: :unprocessable_entity
    end

    @hook.save!
  end

  def destroy
    Current.account.hooks.find_by!(app_id: 'google_translate').destroy!
    head :ok
  end

  private

  def permitted_params
    params.permit(:project_id, credentials: {})
  end
end
