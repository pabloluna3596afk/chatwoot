module Enterprise::Api::V1::Accounts::OnboardingsController
  def show_assistant
    @account = Current.account
    assistant_id = @account.custom_attributes['onboarding_assistant_id']
    @assistant = @account.captain_assistants.find(assistant_id) if assistant_id.present?
    render_assistant_draft
  end

  def create_assistant
    @account = Current.account
    return render_could_not_create_error(I18n.t('onboarding.assistant.invalid')) unless valid_assistant_draft_params?

    @assistant = Onboarding::CaptainDraftService.new(account: @account, **assistant_draft_params.to_h.symbolize_keys).perform
    render_assistant_draft
  rescue Captain::Assistant::LimitExceededError
    limit = @account.plan.max_captain_assistants
    render json: { error: I18n.t('captain.assistant.limit_exceeded', locale: @account.locale, limit: limit),
                   error_code: 'assistant_limit', limit: limit }, status: :unprocessable_entity
  rescue Onboarding::CaptainDraftService::Unavailable
    render_could_not_create_error(I18n.t('onboarding.assistant.unavailable'))
  end

  def help_center_generation
    @account = Current.account
    render json: help_center_generation_status
  end

  private

  def assistant_draft_params
    params.permit(:name, :goal, :tone)
  end

  def valid_assistant_draft_params?
    values = assistant_draft_params
    values[:name].is_a?(String) && values[:name].strip.present? && values[:name].length <= 120 &&
      values[:goal].is_a?(String) && values[:goal].strip.present? && values[:goal].length <= 2000 &&
      Onboarding::CaptainDraftTemplates::TONES.key?(values[:tone])
  end

  def render_assistant_draft
    render 'api/v1/accounts/onboardings/assistant'
  end

  def create_onboarding_inboxes
    super
    create_help_center
  end

  def complete_inbox_setup
    return unless current_step == ::Api::V1::Accounts::OnboardingsController::STEP_INBOX_SETUP

    # Drop the onboarding-only generation pointer; the OSS method's save! persists both deletions.
    @account.custom_attributes.delete('help_center_generation_id')
    super
  end

  def create_help_center
    return if website.blank?

    Onboarding::HelpCenterCreationService.new(@account, Current.user).perform
  end

  def website
    custom_attributes_params[:website]
  end

  def help_center_generation_status
    generation_id = help_center_generation_id
    return super if generation_id.blank?

    state = Onboarding::HelpCenterGenerationState.current(generation_id)

    {
      generation_id: generation_id,
      state: state,
      articles_count: articles_count,
      categories_count: categories_count
    }
  end

  def help_center_generation_id
    @account.custom_attributes['help_center_generation_id']
  end

  def articles_count
    onboarding_portal&.articles&.count || 0
  end

  def categories_count
    onboarding_portal&.categories&.count || 0
  end

  def onboarding_portal
    @onboarding_portal ||= @account.portals.first
  end
end
