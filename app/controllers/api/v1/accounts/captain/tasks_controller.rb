class Api::V1::Accounts::Captain::TasksController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def rewrite
    operation = params[:operation].to_s
    unless Captain::RewriteService::ALLOWED_OPERATIONS.map(&:to_s).include?(operation)
      return render_result({ error: I18n.t('captain.invalid_rewrite_operation'), error_code: 422 })
    end

    result = Captain::RewriteService.new(
      account: Current.account,
      content: params[:content],
      operation: params[:operation],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def summarize
    unless Current.account.conversations.exists?(display_id: params[:conversation_display_id])
      return render_result({ error: I18n.t('captain.conversation_not_found'), error_code: 404 })
    end

    result = Captain::SummaryService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def reply_suggestion
    result = Captain::ReplySuggestionService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id],
      user: Current.user
    ).perform

    render_result(result)
  end

  def label_suggestion
    result = Captain::LabelSuggestionService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def follow_up
    result = Captain::FollowUpService.new(
      account: Current.account,
      follow_up_context: params[:follow_up_context]&.to_unsafe_h,
      user_message: params[:message],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  private

  def render_result(result)
    if result.nil?
      render json: { message: nil }
    elsif result[:error]
      status = task_error_status(result[:error_code])
      code = valid_error_code(result[:error_code]) || Rack::Utils.status_code(status)
      render json: { error: result[:error], error_code: code }, status: status
    else
      response_data = { message: result[:message] }
      response_data[:follow_up_context] = result[:follow_up_context] if result[:follow_up_context]
      render json: response_data
    end
  end

  def task_error_status(error_code)
    return valid_error_code(error_code) if valid_error_code(error_code)

    Current.account.feature_enabled?('captain_tasks') ? :bad_gateway : :forbidden
  end

  def valid_error_code(error_code)
    code = error_code.to_i if error_code.present?
    code if code&.between?(400, 599)
  end

  def check_authorization
    authorize(:'captain/tasks')
  end
end

Api::V1::Accounts::Captain::TasksController.prepend_mod_with('Api::V1::Accounts::Captain::TasksController')
