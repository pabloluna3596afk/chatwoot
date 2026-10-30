module Enterprise::Captain::BaseTaskService
  def perform
    unless captain_tasks_enabled?
      return { error: I18n.t('captain.upgrade') } if ChatwootApp.chatwoot_cloud?

      return { error: I18n.t('captain.disabled') }
    end

    reservation_id = SecureRandom.uuid if counts_toward_usage?
    if reservation_id && !account.reserve_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id)
      return { error: I18n.t('captain.internal_limit'), error_code: 429 }
    end

    begin
      result = Llm::UsageContext.with(
        account: account,
        bucket: :internal,
        feature: event_name,
        context: { conversation_id: conversation&.id }
      ) { super }
    rescue StandardError
      release_reservation(reservation_id)
      raise
    end

    if successful_ai_result?(result)
      account.finish_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id) if reservation_id
    else
      release_reservation(reservation_id)
    end
    result
  end

  private

  def successful_ai_result?(result)
    result.is_a?(Hash) && result[:error].blank? && result['error'].blank? &&
      (result[:message].presence || result['message'].presence)
  end

  def release_reservation(reservation_id)
    return unless reservation_id

    account.release_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id)
  end
end
