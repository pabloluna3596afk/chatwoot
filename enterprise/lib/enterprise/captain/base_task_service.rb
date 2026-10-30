module Enterprise::Captain::BaseTaskService
  def perform
    entitlement = Llm::Entitlement.new(account: account, feature: event_name).call
    return disabled_response unless entitlement[:allowed] || entitlement[:reason] == :usage_limit_reached

    reservation_id = reserve_usage
    return usage_limit_response if reservation_id == false

    begin
      result = perform_with_usage_context(reservation_id) { super }
    rescue StandardError
      release_reservation(reservation_id)
      raise
    end

    if successful_ai_result?(result)
      account.finish_captain_ai_usage!(bucket: usage_bucket, reservation_id: reservation_id) if reservation_id
    else
      release_reservation(reservation_id)
    end
    result
  end

  private

  def disabled_response
    message = ChatwootApp.chatwoot_cloud? ? 'captain.upgrade' : 'captain.disabled'
    { error: I18n.t(message) }
  end

  def reserve_usage
    return unless counts_toward_usage?

    @usage_bucket = Llm::UsageContext.bucket_for(event_name)
    reservation_id = SecureRandom.uuid
    return false unless account.reserve_captain_ai_usage!(bucket: @usage_bucket, reservation_id: reservation_id)

    reservation_id
  end

  def perform_with_usage_context(reservation_id, &)
    Llm::UsageContext.with(
      account: account,
      bucket: usage_bucket,
      feature: event_name,
      context: { conversation_id: conversation&.id, reservation_required: reservation_id.present?, required_gate: 'captain_tasks' },
      reservation_id: reservation_id, &
    )
  end

  def successful_ai_result?(result)
    return false if result.blank?

    if result.is_a?(Hash)
      return false if result[:error].present? || result['error'].present?

      return result.except(:error, :error_code, 'error', 'error_code').values.any?(&:present?)
    end

    true
  end

  def release_reservation(reservation_id)
    return unless reservation_id

    account.release_captain_ai_usage!(bucket: usage_bucket, reservation_id: reservation_id)
  end

  def usage_bucket
    @usage_bucket ||= Llm::UsageContext.bucket_for(event_name)
  end

  def usage_limit_response
    key = usage_bucket == :captain_responses ? 'captain.playground.responses_limit_reached' : 'captain.internal_limit'
    { error: I18n.t(key), error_code: 429 }
  end
end
