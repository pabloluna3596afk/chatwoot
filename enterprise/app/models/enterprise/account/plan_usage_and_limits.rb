module Enterprise::Account::PlanUsageAndLimits # rubocop:disable Metrics/ModuleLength
  CAPTAIN_RESPONSES = 'captain_responses'.freeze
  CAPTAIN_DOCUMENTS = 'captain_documents'.freeze

  def usage_limits
    {
      agents: agent_limits.to_i,
      inboxes: inbox_limits.to_i,
      captain: {
        documents: get_captain_limits(:documents),
        responses: get_captain_limits(:responses),
        storage: get_captain_limits(:storage)
      }
    }
  end

  # Called once per Captain-generated reply (see AccountPlanUsage /
  # Account#current_usage_period for the period/anchor mechanics). No-ops for
  # an account with no plan — nothing to meter, usage_limits already falls
  # back to ChatwootApp.max_limit for those.
  def increment_response_usage(source: :customer)
    current_usage_period&.increment_responses!(source: source)
  end

  # Force-closes the open usage period and reanchors it to now. Historically
  # only called from the Chatwoot Cloud Stripe webhook on subscription
  # renewal; reused for that here via the same reanchor Account uses when an
  # account's plan changes, so both paths can't collide on the same
  # (account_id, period_start) unique index.
  def reset_response_usage
    restart_usage_period
  end

  def update_document_usage
    return unless current_usage_period

    # Update document count
    current_usage_period.set_documents_consumed!(captain_documents.count)

    # Update storage consumption (sum of all document sizes)
    # Since we can't call a Ruby method directly in SQL, we need to calculate it differently
    # Let's load the documents and sum their effective sizes
    total_storage_bytes = captain_documents.reload.to_a.sum(&:effective_size_bytes)
    current_usage_period.set_storage_consumed!(total_storage_bytes)
  end

  def email_transcript_enabled?
    default_plan = InstallationConfig.find_by(name: 'CHATWOOT_CLOUD_PLANS')&.value&.first
    return true if default_plan.blank?

    plan_name.present? && plan_name != default_plan['name']
  end

  def email_rate_limit
    account_limit || plan_email_limit || global_limit || default_limit
  end

  def subscribed_features
    plan_features = InstallationConfig.find_by(name: 'CHATWOOT_CLOUD_PLAN_FEATURES')&.value
    return [] if plan_features.blank?

    plan_features[plan_name]
  end

  def captain_monthly_limit
    default_limits = default_captain_limits

    {
      documents: self[:limits][CAPTAIN_DOCUMENTS] || default_limits['documents'],
      responses: self[:limits][CAPTAIN_RESPONSES] || default_limits['responses'],
      storage: self[:limits]['captain_storage'] || default_limits['storage']
    }.with_indifferent_access
  end

  private

  # `total_count` always reflects the LIVE plan/override configuration (an
  # open period isn't a frozen snapshot); only closed historical periods keep
  # their own limit_responses/limit_documents snapshot for reporting.
  # `consumed` comes from the current usage period, not custom_attributes.
  def get_captain_limits(type)
    total_count = captain_monthly_limit[type.to_s].to_i
    usage = current_usage_period

    consumed = if usage.nil?
                 0
               elsif type == :documents
                 usage.documents_consumed
               elsif type == :storage
                 captain_documents.reload.to_a.sum(&:effective_size_bytes)
               else
                 usage.responses_consumed
               end
    consumed = 0 if consumed.negative?

    {
      total_count: total_count,
      current_available: (total_count - consumed).clamp(0, total_count),
      consumed: consumed
    }
  end

  def plan_email_limit
    return plan.max_emails_per_day if plan.present? && plan.max_emails_per_day.to_i.positive?

    base_limit = plan_base_email_limit
    return nil if base_limit.nil?
    return base_limit if free_plan?

    base_limit * [agent_limits.to_i, 1].max
  end

  def plan_base_email_limit
    config = InstallationConfig.find_by(name: 'ACCOUNT_EMAILS_PLAN_LIMITS')&.value
    return nil if config.blank? || plan_name.blank?

    parsed = config.is_a?(String) ? JSON.parse(config) : config
    parsed[plan_name.downcase]&.to_i
  rescue StandardError
    nil
  end

  def free_plan?
    default_plan = InstallationConfig.find_by(name: 'CHATWOOT_CLOUD_PLANS')&.value&.first
    default_plan.present? && plan_name&.downcase == default_plan['name']&.downcase
  end

  def default_captain_limits
    max_limits = { documents: ChatwootApp.max_limit, responses: ChatwootApp.max_limit, storage: ChatwootApp.max_limit.megabytes }.with_indifferent_access

    # No ChatHub plan assigned yet — don't block the account, fall back to max usage.
    return max_limits if plan.blank?

    {
      documents: plan.max_documents,
      responses: plan.monthly_messages,
      storage: plan.storage_mb.megabytes
    }.with_indifferent_access
  end

  def plan_name
    plan&.slug
  end

  def agent_limits
    subscribed_quantity = custom_attributes['subscribed_quantity']
    return subscribed_quantity if subscribed_quantity.present?

    get_limits(:agents, plan_value: plan&.max_human_agents)
  end

  def inbox_limits
    get_limits(:inboxes, plan_value: plan&.max_inboxes)
  end

  def get_limits(limit_name, plan_value: nil)
    return self[:limits][limit_name.to_s] if self[:limits][limit_name.to_s].present?

    return plan_value if plan_value.present?

    config_name = "ACCOUNT_#{limit_name.to_s.upcase}_LIMIT"
    return GlobalConfig.get(config_name)[config_name] if GlobalConfig.get(config_name)[config_name].present?

    ChatwootApp.max_limit
  end

  def validate_limit_keys
    errors.add(:limits, ': Invalid data') unless self[:limits].is_a? Hash
    self[:limits] = {} if self[:limits].blank?

    limit_schema = {
      'type' => 'object',
      'properties' => {
        'inboxes' => { 'type': 'number' },
        'agents' => { 'type': 'number' },
        'captain_responses' => { 'type': 'number' },
        'captain_documents' => { 'type': 'number' },
        'emails' => { 'type': 'number' },
        'captain_storage' => { 'type': 'number' }
      },
      'required' => [],
      'additionalProperties' => false
    }

    errors.add(:limits, ': Invalid data') unless JSONSchemer.schema(limit_schema).valid?(self[:limits])
  end
end
