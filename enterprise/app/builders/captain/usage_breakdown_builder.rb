class Captain::UsageBreakdownBuilder
  FEATURE_GROUPS = {
    'assistant_action_classifier' => :action_classification,
    'assistant_false_promise_detector' => :action_classification,
    'assistant_migration_instruction_auditor' => :assistant_migration,
    'assistant_migration_instruction_classifier' => :assistant_migration,
    'article_translation' => :article_translation,
    'article_writer' => :article_generation,
    'assistant' => :assistant,
    'assistant_playground' => :assistant_playground,
    'article_search_terms' => :help_center_article_generation,
    'audio_transcription' => :audio_transcription,
    'captain.conversation_completion' => :conversation_completion,
    'captain_assistant_overview_summary' => :assistant_summary,
    'captain_overview_summary' => :assistant_summary,
    'captain_reply' => :captain_reply,
    'contact_attributes' => :contact_attributes,
    'contact_notes' => :contact_notes,
    'content_evaluator' => :content_evaluation,
    'conversation_faq' => :conversation_faq,
    'conversation_faq_match' => :conversation_faq,
    'copilot' => :copilot,
    'copilot_reply' => :copilot_reply,
    'copilot_reply_suggestion' => :copilot_reply,
    'csat_utility_analysis' => :csat_analysis,
    'document_faq_generation' => :document_faq_generation,
    'embedding' => :embeddings,
    'faq_generation' => :document_faq_generation,
    'faq_generator' => :document_faq_generation,
    'follow_up' => :follow_up,
    'help_center_article_generation' => :help_center_article_generation,
    'help_center_curation' => :help_center_curation,
    'help_center_query_translation' => :help_center_query_translation,
    'improve' => :rewrite_message,
    'label_suggestion' => :label_suggestion,
    'language_detection' => :language_detection,
    'message_translation' => :message_translation,
    'onboarding_content_generation' => :onboarding_content_generation,
    'paginated_faq_generation' => :document_faq_generation,
    'professional' => :rewrite_message,
    'casual' => :rewrite_message,
    'friendly' => :rewrite_message,
    'confident' => :rewrite_message,
    'straightforward' => :rewrite_message,
    'fix_spelling_grammar' => :rewrite_message,
    'reply_suggestion' => :rewrite_message,
    'summary' => :conversation_summary,
    'summarize' => :conversation_summary,
    'translate_query' => :translate_query,
    'website_analyzer' => :website_analysis,
    'widget_tagline' => :widget_tagline
  }.freeze
  BUCKETS = Llm::UsageFeatureBuckets::FEATURE_BUCKETS.values.uniq.map(&:to_s).freeze

  def initialize(account:, period:, bucket: nil)
    @account = account
    @period = period
    @bucket = bucket&.to_s
  end

  def build
    return empty_result unless period

    rows = event_rows
    buckets = build_buckets(rows)
    { period_start: period.period_start, period_end: period.period_end, buckets: buckets }
  end

  private

  attr_reader :account, :period, :bucket

  def event_rows
    events = AiUsageEvent.where(account_id: account.id, status: 'ok', created_at: period.period_start...period.period_end)
    events = events.where(bucket: bucket) if bucket
    events.pluck(:bucket, :feature, :usage_group_id, :units, :created_at)
  end

  def build_buckets(rows)
    buckets = BUCKETS.index_with { [] }
    grouped_events(rows).each do |(event_bucket, feature_group, _group_id), group_events|
      buckets[event_bucket] << operation_summary(feature_group, group_events)
    end
    buckets.transform_values! { |features| summarize_features(features) }
    bucket ? buckets.slice(bucket) : buckets
  end

  def grouped_events(rows)
    rows.group_by do |event_bucket, feature, group_id, _units, _created_at|
      [event_bucket, FEATURE_GROUPS.fetch(feature), group_id]
    end
  end

  def operation_summary(feature_group, events)
    { feature: feature_group, units: events.pluck(3).max, last_used_at: events.pluck(4).max }
  end

  def summarize_features(features)
    grouped_features = features.group_by { |feature| feature[:feature] }
    summaries = grouped_features.map do |feature_group, operations|
      feature_summary(feature_group, operations)
    end
    summaries.sort_by { |feature| [-feature[:units], -feature[:operations], feature[:feature]] }
  end

  def feature_summary(feature_group, operations)
    {
      feature: feature_group,
      name: I18n.t("captain.usage_breakdown.features.#{feature_group}"),
      operations: operations.size,
      units: operations.sum { |operation| operation[:units] },
      last_used_at: operations.pluck(:last_used_at).max
    }
  end

  def empty_result
    selected_buckets = bucket ? [bucket] : BUCKETS
    { period_start: nil, period_end: nil, buckets: selected_buckets.index_with { [] } }
  end
end
