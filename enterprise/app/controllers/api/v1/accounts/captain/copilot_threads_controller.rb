class Api::V1::Accounts::Captain::CopilotThreadsController < Api::V1::Accounts::BaseController
  include Captain::Copilot::ConversationAccess

  before_action :ensure_captain_integration_enabled, only: :index
  before_action :ensure_assistant_id, only: :create
  before_action :ensure_message, only: :create
  before_action :ensure_accessible_conversation, only: :create
  before_action :ensure_entitlement, only: :create

  def index
    @copilot_threads = Current.account.copilot_threads
                              .where(user_id: Current.user.id)
                              .includes(:user, :assistant)
                              .order(created_at: :desc)
                              .page(permitted_params[:page] || 1)
                              .per(5)
  end

  def create
    ActiveRecord::Base.transaction do
      @copilot_thread = Current.account.copilot_threads.create!(
        title: copilot_thread_params[:message].truncate(ApplicationRecord::MAX_STRING_COLUMN_LENGTH, omission: ''),
        user: Current.user,
        assistant: resolved_assistant
      )

      copilot_message = @copilot_thread.copilot_messages.create!(
        message_type: :user,
        message: { content: copilot_thread_params[:message] }
      )

      enqueue_copilot_response(copilot_message)
    end
  end

  private

  def enqueue_copilot_response(copilot_message)
    return enqueue_reply_suggestion if reply_suggestion?

    copilot_message.enqueue_response_job(copilot_thread_params[:conversation_id], Current.user.id)
  end

  def enqueue_reply_suggestion
    Captain::Copilot::ReplySuggestionJob.perform_later(
      assistant: @copilot_thread.assistant,
      conversation_id: copilot_thread_params[:conversation_id],
      user_id: Current.user.id,
      copilot_thread_id: @copilot_thread.id
    )
  end

  def ensure_message
    return render_could_not_create_error(I18n.t('captain.copilot_message_required')) if copilot_thread_params[:message].blank?
  end

  def ensure_assistant_id
    return unless params.key?(:assistant_id)
    return if params[:assistant_id].is_a?(Integer) || params[:assistant_id].is_a?(String)

    render_could_not_create_error(I18n.t('captain.copilot_assistant_invalid'))
  end

  def ensure_accessible_conversation
    return unless reply_suggestion?

    conversation = accessible_conversation(
      account: Current.account,
      user: Current.user,
      display_id: copilot_thread_params[:conversation_id]
    )
    raise ActiveRecord::RecordNotFound, 'Conversation not found' if conversation.blank?
  end

  def reply_suggestion?
    copilot_thread_params[:request_type] == 'reply_suggestion'
  end

  def resolved_assistant
    Captain::Copilot::AssistantResolver.new(
      account: Current.account,
      assistant_id: copilot_thread_params[:assistant_id]
    ).perform
  end

  def copilot_thread_params
    params.permit(:message, :assistant_id, :conversation_id, :request_type)
  end

  def permitted_params
    params.permit(:page)
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
