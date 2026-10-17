class Onboarding::CaptainDraftService
  class Unavailable < StandardError; end

  def initialize(account:, name:, goal:, tone:)
    @account = account
    @name = name
    @goal = goal
    @tone = tone
  end

  def perform
    @account.with_lock do
      raise Unavailable unless eligible?

      assistant_id = @account.custom_attributes['onboarding_assistant_id']
      assistant = assistant_id ? @account.captain_assistants.find(assistant_id) : @account.captain_assistants.new
      # Replays after activation must never overwrite a live assistant.
      return assistant if assistant.persisted? && assistant.captain_inboxes.exists?

      assistant.assign_attributes(
        name: @name, description: @goal.truncate(Captain::Assistant::DESCRIPTION_LENGTH_LIMIT),
        response_guidelines: Onboarding::CaptainDraftTemplates.instructions(account: @account, goal: @goal, tone: @tone),
        guardrails: Onboarding::CaptainDraftTemplates::GUARDRAILS,
        config: assistant.config.merge(draft_config)
      )
      assistant.save!
      @account.custom_attributes['onboarding_assistant_id'] = assistant.id
      @account.save!
      assistant
    end
  end

  private

  def eligible?
    @account.custom_attributes['onboarding_version'] == 2 && @account.custom_attributes['onboarding_step'] == 'assistant' &&
      @account.feature_enabled?('captain_integration') && @account.feature_enabled?('captain_integration_v2')
  end

  def draft_config
    {
      'product_name' => @account.name,
      'onboarding' => { 'goal' => @goal, 'tone' => @tone },
      'feature_faq' => false, 'feature_memory' => false, 'feature_citation' => false, 'feature_contact_attributes' => false,
      'auto_resolve_mode' => 'disabled', 'send_inactivity_resolution_message' => false,
      'allow_paid_templates' => false, 'appointments' => { 'enabled' => false },
      'followup' => { 'inactivity_enabled' => false, 'reengagement_enabled' => false }
    }
  end
end
