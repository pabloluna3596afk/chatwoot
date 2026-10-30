module Captain::ChatUsageContext
  def request_chat_completion
    bucket = Llm::UsageFeatureBuckets::FEATURE_BUCKETS.fetch(feature_name.to_s)
    # This module wraps a Captain service method; these are service state values, not view locals.
    # rubocop:disable Rails/HelperInstanceVariable
    Llm::UsageContext.with(
      account: @account || @assistant&.account,
      bucket: bucket,
      feature: feature_name,
      context: { conversation_id: @conversation&.id },
      usage_group_id: (@ai_usage_group_id ||= SecureRandom.uuid)
    ) do
      request_chat_completion_with_usage_context
    end
    # rubocop:enable Rails/HelperInstanceVariable
  end
end
