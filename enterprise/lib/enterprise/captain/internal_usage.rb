module Enterprise::Captain::InternalUsage
  private

  def with_internal_usage(account:, feature:, conversation_id: nil, &)
    reservation_id = reserve_internal_usage(account)
    return if reservation_id == false

    result = Llm::UsageContext.with(
      account: account,
      bucket: :internal,
      feature: feature,
      context: { conversation_id: conversation_id, reservation_required: reservation_id.present? },
      reservation_id: reservation_id,
      &
    )
    account.finish_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id) if reservation_id
    result
  rescue StandardError
    account.release_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id) if reservation_id
    raise
  end

  def reserve_internal_usage(account)
    unless internal_usage_reservation_required?(account)
      return account.reserve_captain_ai_usage!(bucket: :internal) ? nil : false
    end

    reservation_id = SecureRandom.uuid
    account.reserve_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id) ? reservation_id : false
  end

  def internal_usage_reservation_required?(account)
    account.current_usage_period.present? && account.usage_limits.dig(:captain, :internal, :total_count).present?
  end
end
