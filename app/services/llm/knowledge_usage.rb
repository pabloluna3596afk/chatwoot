# Share the existing durable reservation lifecycle across knowledge entry points.
class Llm::KnowledgeUsage
  class QuotaExceeded < StandardError; end

  def self.with_reserved(account:, feature:, units:, context: {}, &)
    reservation_id = SecureRandom.uuid
    reserved = account.reserve_captain_ai_usage!(bucket: :internal, units: units, reservation_id: reservation_id)
    raise QuotaExceeded, I18n.t('captain.documents.usage_quota_exceeded') unless reserved

    result = Llm::UsageContext.with(
      account: account, feature: feature, bucket: :internal, units: units, reservation_id: reservation_id,
      context: context.merge(reservation_required: receipt_required?(account)), &
    )
    if result.is_a?(Hash) && (result[:error].present? || result[:success] == false)
      account.release_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id)
    else
      account.finish_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id)
    end
    result
  rescue StandardError
    account.release_captain_ai_usage!(bucket: :internal, reservation_id: reservation_id) if reserved
    raise
  end

  def self.with_included_matching(account:, &)
    usage = Llm::UsageContext.current
    Llm::UsageContext.with(
      account: account, feature: 'conversation_faq_match', units: Llm::UnitCosts.fetch(:conversation_faq_match),
      reservation_id: usage[:reservation_id], usage_group_id: usage[:usage_group_id],
      context: usage.slice(:conversation_id, :reservation_required), &
    )
  end

  def self.receipt_required?(account)
    account.current_usage_period.present? && account.usage_limits.dig(:captain, :internal, :total_count).present?
  end
  private_class_method :receipt_required?
end
