module Enterprise::Captain::BaseTaskService
  def perform
    unless captain_tasks_enabled?
      return { error: I18n.t('captain.upgrade') } if ChatwootApp.chatwoot_cloud?

      return { error: I18n.t('captain.disabled') }
    end

    if counts_toward_usage? && !account.reserve_captain_ai_usage!(bucket: :internal)
      return { error: I18n.t('captain.internal_limit'), error_code: 429 }
    end

    Llm::UsageContext.with(
      account: account,
      bucket: :internal,
      feature: event_name,
      context: { conversation_id: conversation&.id }
    ) { super }
  end
end
