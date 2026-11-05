# frozen_string_literal: true

require 'rails_helper'
require 'support/llm/usage_feature_decisions'

module Llm::UsageFeatureContract
  FEATURE_DECISIONS = Llm::UsageFeatureDecisions::FEATURE_DECISIONS
  VALID_BUCKETS = %i[internal captain_responses copilot].freeze

  # These services are measured, but intentionally have no quota reservation yet. Each entry
  # records why it remains an exception; adding a measure_only feature requires an explicit review.
  MEASURE_ONLY_EXCEPTIONS = {
    'article_writer' => 'Legacy article writing records usage but has no reservation flow.',
    'captain.conversation_completion' => 'Background completion records usage without a user quota reservation.',
    'captain_assistant_overview_summary' => 'Background overview summaries record usage without a quota reservation.',
    'captain_overview_summary' => 'Background overview summaries record usage without a quota reservation.',
    'conversation_faq' => 'FAQ suggestion generation records usage without a quota reservation.',
    'conversation_faq_match' => 'FAQ matching records usage without a quota reservation.',
    'document_faq_generation' => 'Document FAQ generation records usage without a quota reservation.',
    'embedding' => 'Embeddings are measured internally and do not consume a response reservation.',
    'faq_generation' => 'Legacy FAQ generation records usage without a quota reservation.',
    'faq_generator' => 'FAQ generation records usage without a quota reservation.',
    'help_center_article_generation' => 'Article generation records usage without a quota reservation.',
    'help_center_curation' => 'Help center curation records usage without a quota reservation.',
    'help_center_query_translation' => 'Query translation records usage without a quota reservation.',
    'onboarding_content_generation' => 'Onboarding content records usage without a quota reservation.',
    'paginated_faq_generation' => 'Paginated FAQ generation records usage without a quota reservation.',
    'translate_query' => 'Legacy query translation records usage without a quota reservation.',
    'website_analyzer' => 'Website analysis records usage without a quota reservation.',
    'widget_tagline' => 'Widget tagline generation records usage without a quota reservation.'
  }.freeze

  CONFIG_FEATURE_BUCKETS = {
    'conversation_completion' => %w[captain.conversation_completion],
    'editor' => %w[
      casual confident csat_utility_analysis fix_spelling_grammar follow_up friendly improve label_suggestion
      professional reply_suggestion straightforward summary summarize
    ],
    'assistant' => %w[assistant captain_reply],
    'copilot' => %w[copilot],
    'label_suggestion' => %w[label_suggestion],
    'document_faq_generation' => %w[document_faq_generation],
    'conversation_faq_generation' => %w[conversation_faq],
    'conversation_faq_matching' => %w[conversation_faq_match],
    'pdf_faq_generation' => %w[faq_generation paginated_faq_generation],
    'help_center_article_generation' => %w[help_center_article_generation],
    'onboarding_content_generation' => %w[onboarding_content_generation],
    'help_center_query_translation' => %w[help_center_query_translation],
    'message_translation' => %w[message_translation],
    'language_detection' => %w[language_detection],
    'audio_transcription' => %w[audio_transcription]
  }.freeze

  # The setting remains for the help center's semantic-search configuration; current search
  # execution does not resolve or call an LLM feature through this key.
  CONFIG_FEATURES_WITHOUT_LLM_CALL = %w[help_center_search].freeze
end

RSpec.describe Llm::UsageFeatureContract do
  describe 'feature bucket and decision inventory' do
    let(:feature_buckets) { Llm::UsageFeatureBuckets::FEATURE_BUCKETS }
    let(:decision_labels) do
      described_class::FEATURE_DECISIONS.flat_map do |decision, features|
        features.map { |feature| [feature, decision] }
      end.to_h
    end

    it 'gives every bucket feature one decision and rejects orphan decisions' do
      expect(feature_buckets.values).to all(be_in(described_class::VALID_BUCKETS))
      expect(decision_labels.keys.sort).to eq(feature_buckets.keys.sort)
    end

    it 'keeps measure_only features in the reviewed exception list' do
      expect(described_class::FEATURE_DECISIONS.fetch(:measure_only).sort)
        .to eq(described_class::MEASURE_ONLY_EXCEPTIONS.keys.sort)
      expect(described_class::MEASURE_ONLY_EXCEPTIONS.values).to all(be_present)
    end

    it 'routes every measure_and_limit feature through its matching entitlement gate and allowance' do
      expected_allowance = { internal: :internal, captain_responses: :responses, copilot: :copilot }

      described_class::FEATURE_DECISIONS.fetch(:measure_and_limit).each do |feature|
        bucket = feature_buckets.fetch(feature)
        entitlement = Llm::Entitlement.new(account: Object.new, feature: feature)
        expected_gate = if Llm::Entitlement::TASK_FEATURE_GATES.include?(feature)
                          'captain_tasks'
                        else
                          Llm::Entitlement::FEATURE_GATES.fetch(bucket)
                        end

        expect(entitlement.instance_variable_get(:@bucket)).to eq(bucket), feature
        expect(entitlement.instance_variable_get(:@required_gate)).to eq(expected_gate), feature
        expect(entitlement.send(:usage_limit_key)).to eq(expected_allowance.fetch(bucket)), feature
      end
    end
  end

  describe 'config/llm.yml feature inventory' do
    it 'maps every configured LLM feature to a metered bucket or a documented non-LLM setting' do
      configured_features = YAML.load_file(Rails.root.join('config/llm.yml')).fetch('features').keys
      explicitly_classified = described_class::CONFIG_FEATURE_BUCKETS.keys +
                              described_class::CONFIG_FEATURES_WITHOUT_LLM_CALL

      expect(explicitly_classified.sort).to eq(configured_features.sort)
      described_class::CONFIG_FEATURE_BUCKETS.each do |config_feature, bucket_features|
        expect(bucket_features).not_to be_empty, config_feature
        expect(bucket_features).to all(be_in(Llm::UsageFeatureBuckets::FEATURE_BUCKETS.keys)), config_feature
      end
    end
  end
end
