module Enterprise::Api::V1::Accounts::ConversationsController
  extend ActiveSupport::Concern

  prepended do
    before_action :validate_auto_translate_switch, only: :update # rubocop:disable Rails/LexicallyScopedActionFilter
  end

  def inbox_assistant
    assistant = @conversation.inbox.captain_assistant

    if assistant
      render json: { assistant: { id: assistant.id, name: assistant.name } }
    else
      render json: { assistant: nil }
    end
  end

  def reporting_events
    @reporting_events = @conversation.reporting_events.order(created_at: :asc)
  end

  def transcribe_audio
    attachment = @conversation.attachments.audio.find(params.require(:attachment_id))
    result = Messages::AudioTranscriptionService.new(attachment).perform(manual: true)
    status = result[:error] ? :unprocessable_entity : :ok
    render json: result, status: status
  end

  def permitted_update_params
    permitted = super
    permitted = permitted.merge(params.permit(:sla_policy_id)) if Current.account.feature_enabled?('sla')
    permitted = permitted.merge(params.permit(:auto_translate_disabled)) if conversation_translation_control?
    permitted
  end

  private

  def conversation_translation_control?
    Current.account.feature_enabled?('conversation_auto_translate') && Current.account.auto_translate_enabled?
  end

  def validate_auto_translate_switch
    return unless conversation_translation_control? && params.key?(:auto_translate_disabled)
    return if [true, false].include?(params[:auto_translate_disabled])

    render_could_not_create_error(I18n.t('errors.auto_translate.invalid_setting'))
  end

  def copilot_params
    params.permit(:previous_history, :message, :assistant_id)
  end
end
