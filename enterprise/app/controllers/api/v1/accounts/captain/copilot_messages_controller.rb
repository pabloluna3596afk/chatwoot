class Api::V1::Accounts::Captain::CopilotMessagesController < Api::V1::Accounts::BaseController
  before_action :ensure_captain_integration_enabled, only: :index
  before_action :ensure_message_length, only: :create
  before_action :ensure_entitlement, only: :create
  before_action :set_copilot_thread

  def index
    @copilot_messages = @copilot_thread
                        .copilot_messages
                        .includes(:copilot_thread)
                        .order(created_at: :asc)
                        .page(permitted_params[:page] || 1)
                        .per(1000)
  end

  def create
    @copilot_message = @copilot_thread.copilot_messages.create!(
      message: { content: params[:message] },
      message_type: :user
    )
    @copilot_message.enqueue_response_job(params[:conversation_id], Current.user.id)
  end

  private

  def set_copilot_thread
    @copilot_thread = Current.account.copilot_threads.find_by!(
      id: params[:copilot_thread_id],
      user: Current.user
    )
  end

  def permitted_params
    params.permit(:page)
  end

  def ensure_message_length
    return if params[:message].is_a?(String) && params[:message].length <= Captain::Copilot::Limits::USER_MESSAGE_CHARACTERS

    render json: { error: I18n.t('captain.copilot_message_too_long') }, status: :unprocessable_entity
  end

  def ensure_captain_integration_enabled
    decision = Llm::Entitlement.new(account: Current.account, feature: 'copilot').call
    return unless decision[:reason] == :feature_disabled

    render json: { error: decision[:error] }, status: decision[:error_code]
  end

  def ensure_entitlement
    decision = Llm::Entitlement.new(account: Current.account, feature: 'copilot').call
    return if decision[:allowed]

    render json: { error: decision[:error] }, status: decision[:error_code]
  end
end
