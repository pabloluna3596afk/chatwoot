# Fails provider calls that bypass the account usage context in tests and CI.
class Llm::UnmeteredCall < StandardError; end

module Llm::MeteringGuard
  extend self

  # Guard decisions intentionally stay at the provider boundary.
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def check!
    context = Llm::UsageContext.current
    errors = context_errors(context)
    return record_trace(context) if errors.empty?

    message = "Unmetered AI provider call: #{errors.join(', ')}"
    raise Llm::UnmeteredCall, message if Rails.env.test? || ENV['CI'].present?

    unmapped = errors.any? { |error| error.include?('feature') || error.include?('bucket') || error.include?('Unmapped AI usage feature') }
    context[:bucket] = 'unmapped' if unmapped && context
    Rails.logger.error(message)
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  private

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def context_errors(context)
    return ['missing context'] unless context

    errors = []
    errors << 'missing account' if context[:account_id].blank?
    feature = context[:feature].to_s
    errors << 'missing feature' if feature.blank?
    mapped_bucket = Llm::UsageContext.bucket_for(feature)
    errors << 'bucket mismatch' unless context[:bucket].to_s == mapped_bucket.to_s
    if context[:reservation_required]
      errors << 'missing reservation receipt' if context[:reservation_id].blank?
      errors << 'inactive reservation receipt' if context[:reservation_id].present? && !reservation_exists?(context)
    end
    errors
  rescue ArgumentError => e
    [e.message]
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def reservation_exists?(context)
    AiUsageReservation.joins(:account_plan_usage).exists?(
      reservation_id: context[:reservation_id], bucket: context[:bucket],
      account_plan_usages: { account_id: context[:account_id], closed_at: nil }
    )
  end

  def record_trace(context)
    return unless (Rails.env.test? || ENV['CI'].present?) && ENV['LLM_METERING_TRACE'] == '1'

    trace = Thread.current[:llm_metering_trace] ||= []
    trace << {
      caller: caller_locations(2, 12).map(&:to_s), account_id: context[:account_id],
      bucket: context[:bucket], feature: context[:feature],
      reservation_id: context[:reservation_id], reservation_required: context[:reservation_required],
      gate: context[:required_gate], plan: context[:required_plan]
    }
  end
end
