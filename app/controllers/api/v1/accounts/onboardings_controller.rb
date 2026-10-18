class Api::V1::Accounts::OnboardingsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :validate_business_details, only: :update
  before_action :validate_inbox_setup_result, only: :update

  ONBOARDING_STEP_KEY = 'onboarding_step'.freeze
  STEP_ACCOUNT_DETAILS = 'account_details'.freeze
  STEP_INBOX_SETUP = 'inbox_setup'.freeze
  ONBOARDING_STEPS = [STEP_ACCOUNT_DETAILS, STEP_INBOX_SETUP].freeze
  BUSINESS_TYPES = %w[appointments commerce services other].freeze
  INBOX_SETUP_RESULTS = %w[whatsapp_connected skipped].freeze

  def update
    return render json: { error: 'Invalid onboarding step' }, status: :unprocessable_entity unless ONBOARDING_STEPS.include?(params[:onboarding_step])

    @account = Current.account
    # The client declares the step it is completing; `account_details` runs
    # `complete_account_details`, and so on. The known-step guard above keeps the
    # client value from `send`-ing an arbitrary method.
    send("complete_#{params[:onboarding_step]}")

    render 'api/v1/accounts/update', format: :json
  end

  def help_center_generation
    render json: help_center_generation_status
  end

  private

  def validate_business_details
    return unless params[:onboarding_step] == STEP_ACCOUNT_DETAILS
    return unless Current.account.custom_attributes[ONBOARDING_STEP_KEY] == STEP_ACCOUNT_DETAILS

    return render_could_not_create_error('Invalid business type') if invalid_business_type?

    render_could_not_create_error('Invalid country') if invalid_country?
  end

  def invalid_business_type?
    params.key?(:business_type) && BUSINESS_TYPES.exclude?(params[:business_type])
  end

  def invalid_country?
    params.key?(:country) && params[:country] != '' && TZInfo::Country.all_codes.exclude?(params[:country])
  end

  def validate_inbox_setup_result
    return unless Current.account.custom_attributes['onboarding_version'] == 2
    return unless params[:onboarding_step] == STEP_INBOX_SETUP
    return unless Current.account.custom_attributes[ONBOARDING_STEP_KEY] == STEP_INBOX_SETUP
    return if INBOX_SETUP_RESULTS.include?(params[:inbox_setup_result])

    render_could_not_create_error('Invalid inbox setup result')
  end

  def complete_account_details
    # Only act while the cursor still points here, so a stale replay after
    # onboarding finished can't re-enter it.
    return unless current_step == STEP_ACCOUNT_DETAILS

    @account.assign_attributes(account_params)
    @account.custom_attributes.merge!(custom_attributes_params)

    if onboarding_v2?
      move_to_step(STEP_INBOX_SETUP)
    elsif ChatwootApp.chatwoot_cloud?
      move_to_step(STEP_INBOX_SETUP)
      create_onboarding_inboxes
    else
      finish_onboarding
    end
  end

  def complete_inbox_setup
    # Only finalize while the cursor still points here, so a stale or out-of-order
    # request can't end onboarding early. Replays are no-ops.
    return unless current_step == STEP_INBOX_SETUP

    Onboarding::InboxMemberAssignmentService.new(@account, Current.account_user).perform
    @account.custom_attributes['inbox_setup_result'] = params[:inbox_setup_result] if onboarding_v2?

    finish_onboarding
  end

  def onboarding_v2?
    @account.custom_attributes['onboarding_version'] == 2
  end

  def current_step
    @account.custom_attributes[ONBOARDING_STEP_KEY]
  end

  def move_to_step(step)
    @account.custom_attributes[ONBOARDING_STEP_KEY] = step
    @account.save!
  end

  def finish_onboarding
    @account.custom_attributes.delete(ONBOARDING_STEP_KEY)
    @account.save!
  end

  def create_onboarding_inboxes
    Onboarding::WebWidgetCreationService.new(@account, Current.user).perform
  end

  def account_params
    params.permit(:name, :locale)
  end

  def custom_attributes_params
    params.permit(:industry, :company_size, :timezone, :referral_source, :user_role, :website, :business_type, :country)
  end

  def help_center_generation_status
    {
      generation_id: nil,
      state: nil,
      articles_count: 0,
      categories_count: 0
    }
  end
end

Api::V1::Accounts::OnboardingsController.prepend_mod_with('Api::V1::Accounts::OnboardingsController')
