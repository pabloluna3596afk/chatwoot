# frozen_string_literal: true

module Llm::UsageFeatureDecisions
  FEATURE_DECISIONS = {
    measure_and_limit: %w[
      conversation_faq conversation_faq_match document_faq_generation faq_generation faq_generator paginated_faq_generation
      translate_query website_analyzer
      assistant assistant_action_classifier assistant_playground article_translation audio_transcription captain_reply
      copilot copilot_reply copilot_reply_suggestion csat_utility_analysis follow_up improve label_suggestion
      message_translation professional casual friendly confident straightforward fix_spelling_grammar reply_suggestion
      summary summarize language_detection contact_notes contact_attributes assistant_false_promise_detector
      assistant_migration_instruction_classifier assistant_migration_instruction_auditor content_evaluator
    ],
    measure_only: %w[
      article_writer article_search_terms captain.conversation_completion captain_assistant_overview_summary captain_overview_summary
      embedding
      help_center_article_generation help_center_curation
      help_center_query_translation onboarding_content_generation
      widget_tagline
    ],
    prohibit: []
  }.freeze
end
