# frozen_string_literal: true

require 'rails_helper'
require 'csv'

module AiCertification; end

module AiCertification::AssistantAndBackground
  FEATURE_DECISIONS = {
    measure_and_limit: %w[
      assistant assistant_action_classifier assistant_playground article_translation audio_transcription captain_reply
      copilot copilot_reply copilot_reply_suggestion csat_utility_analysis follow_up improve label_suggestion
      message_translation professional casual friendly confident straightforward fix_spelling_grammar reply_suggestion
      summary
    ],
    measure_only: %w[
      assistant_false_promise_detector assistant_migration_instruction_auditor
      assistant_migration_instruction_classifier article_writer captain.conversation_completion
      captain_assistant_overview_summary captain_overview_summary contact_attributes contact_notes
      content_evaluator conversation_faq conversation_faq_match document_faq_generation embedding
      faq_generation faq_generator help_center_article_generation help_center_curation
      help_center_query_translation language_detection onboarding_content_generation paginated_faq_generation
      summarize translate_query website_analyzer widget_tagline
    ],
    prohibit: []
  }.freeze

  INSTRUMENTED_CALLERS = %w[
    enterprise/app/services/captain/llm/assistant_action_classifier_service.rb
    enterprise/app/services/captain/llm/assistant_false_promise_service.rb
    enterprise/app/services/captain/llm/contact_attributes_service.rb
    enterprise/app/services/captain/llm/contact_notes_service.rb
    enterprise/app/services/captain/llm/conversation_faq_service.rb
    enterprise/app/services/captain/llm/embedding_service.rb
    enterprise/app/services/captain/llm/faq_generator_service.rb
    enterprise/app/services/captain/llm/paginated_faq_generator_service.rb
    enterprise/app/services/captain/onboarding/website_analyzer_service.rb
    enterprise/app/services/captain/assistant/agent_runner_service.rb
    enterprise/app/services/captain/assistant/response_rewriter.rb
    enterprise/app/helpers/captain/chat_helper.rb
    enterprise/app/services/internal/account_analysis/content_evaluator_service.rb
    enterprise/app/services/llm/speech_to_text_service.rb
    lib/integrations/llm_base_service.rb
  ].freeze

  CALLSITE_ROOTS = %w[
    app/helpers app/services enterprise/app/helpers/captain enterprise/app/services/captain
    enterprise/app/services/internal enterprise/app/services/llm lib/captain lib/integrations
  ].freeze

  SCENARIOS = %w[
    success provider_error mid_call_exception empty_response malformed_or_duplicate_json exhausted no_flag_or_plan
    null_bucket retry concurrency
  ].freeze

  FLOWS = [
    'assistant V1 response (delivery stubbed)', 'assistant V2 response (delivery stubbed)', 'action classifier',
    'auto-resolve evaluator', 'playground', 'FAQ and documents', 'embeddings and moderation',
    'audio transcription', 'legacy Integrations::LlmBaseService'
  ].freeze

  DECISION_LABELS = FEATURE_DECISIONS.flat_map do |decision, features|
    features.map { |feature| [feature, decision] }
  end.to_h.freeze
end

RSpec.shared_examples 'a documented metered feature' do |feature, bucket, decision|
  it "maps #{feature} to its documented provider bucket" do
    expect(Llm::UsageContext.bucket_for(feature)).to eq(bucket)
    expect(decision).to be_in(%i[measure_and_limit measure_only prohibit])
  end
end

RSpec.describe AiCertification::AssistantAndBackground do
  Llm::UsageFeatureBuckets::FEATURE_BUCKETS.each do |feature, bucket|
    it_behaves_like 'a documented metered feature', feature, bucket,
                    AiCertification::AssistantAndBackground::DECISION_LABELS.fetch(feature)
  end

  describe 'usage feature inventory' do
    it 'documents a quota decision for every feature bucket' do
      bucket_features = Llm::UsageFeatureBuckets::FEATURE_BUCKETS.keys.sort
      decisions = AiCertification::AssistantAndBackground::DECISION_LABELS.keys.sort

      expect(decisions).to eq(bucket_features)
      expect(AiCertification::AssistantAndBackground::FEATURE_DECISIONS.keys)
        .to match_array(%i[measure_and_limit measure_only prohibit])
    end

    it 'keeps the instrumented provider callsite inventory explicit' do
      pattern = /(?:instrument_(?:llm|embedding|moderation)_call|instrument_agent_session|
        instrument_audio_transcription|with_usage_recording|runner\.run)\s*\(/x
      caller_paths = AiCertification::AssistantAndBackground::CALLSITE_ROOTS.flat_map do |root|
        Dir.glob(Rails.root.join(root, '**', '*.rb')).filter_map do |path|
          relative_path = Pathname.new(path).relative_path_from(Rails.root).to_s.tr('\\', '/')
          relative_path if File.read(path).match?(pattern)
        end
      end
      callers = caller_paths.uniq.reject do |path|
        path.start_with?('lib/integrations/llm_instrumentation', 'lib/integrations/llm_usage_recording')
      end.sort

      expect(callers).to eq(AiCertification::AssistantAndBackground::INSTRUMENTED_CALLERS.sort)
    end

    it 'allows each mapped feature through the provider guard and records its usage event', :aggregate_failures do
      account = create(:account)
      trace_before = Thread.current[:llm_metering_trace]
      Thread.current[:llm_metering_trace] = []
      previous_trace_setting = ENV.fetch('LLM_METERING_TRACE', nil)
      ENV['LLM_METERING_TRACE'] = '1'

      Llm::UsageFeatureBuckets::FEATURE_BUCKETS.each do |feature, bucket|
        Llm::UsageContext.with(account: account, feature: feature, bucket: bucket) do
          expect { Llm::MeteringGuard.check! }.not_to raise_error
          Llm::UsageContext.record_operation(model: 'gpt-test', provider: 'openai', status: 'ok', response: nil)
        end
      end

      trace = Thread.current[:llm_metering_trace]
      expect(AiUsageEvent.where(account: account).count).to eq(Llm::UsageFeatureBuckets::FEATURE_BUCKETS.size)
      expect(trace.size).to eq(Llm::UsageFeatureBuckets::FEATURE_BUCKETS.size)
      trace.each do |entry|
        expect(entry[:account_id]).to eq(account.id)
        expect(entry[:bucket].to_sym).to eq(Llm::UsageFeatureBuckets::FEATURE_BUCKETS.fetch(entry[:feature]))
        expect(AiCertification::AssistantAndBackground::DECISION_LABELS).to have_key(entry[:feature])
      end
      write_inventory_csv(trace)
    ensure
      Thread.current[:llm_metering_trace] = trace_before
      ENV['LLM_METERING_TRACE'] = previous_trace_setting
    end

    it 'rejects provider calls without context, a mapped bucket, or a required reservation receipt' do
      account = create(:account)

      expect { Llm::MeteringGuard.check! }.to raise_error(Llm::UnmeteredCall, /missing context/)
      expect do
        Llm::UsageContext.with_instrumentation(account: account, feature_name: 'unreviewed_background_call') do
          Llm::MeteringGuard.check!
        end
      end.to raise_error(Llm::UnmeteredCall, /Unmapped AI usage feature/)
      expect do
        Llm::UsageContext.with(
          account: account, feature: 'copilot', bucket: :copilot,
          context: { reservation_required: true }
        ) { Llm::MeteringGuard.check! }
      end.to raise_error(Llm::UnmeteredCall, /missing reservation receipt/)
    end

    it 'stops instrumented LLM calls before reaching a provider without context' do
      caller = Class.new { include Integrations::LlmInstrumentation }.new
      provider_called = false

      expect do
        caller.instrument_llm_call({}) { provider_called = true }
      end.to raise_error(Llm::UnmeteredCall, /missing context/)
      expect(provider_called).to be(false)
      expect do
        caller.instrument_agent_session({}) { provider_called = true }
      end.to raise_error(Llm::UnmeteredCall, /missing context/)
      expect(provider_called).to be(false)
    end
  end

  describe 'scenario inventory' do
    it 'emits a CSV row for every flow and required certification scenario' do
      rows = AiCertification::AssistantAndBackground::FLOWS.flat_map do |flow|
        AiCertification::AssistantAndBackground::SCENARIOS.map do |scenario|
          [flow, scenario, 'correlated usage/reservation contract', 'not exercised in this inventory pass',
           exclusion_reason(scenario), 'EXCLUDED']
        end
      end

      expect(rows.size).to eq(
        AiCertification::AssistantAndBackground::FLOWS.size * AiCertification::AssistantAndBackground::SCENARIOS.size
      )
      write_scenario_csv(rows)
    end
  end

  def write_inventory_csv(trace)
    rows = trace.map do |entry|
      [entry[:feature], entry[:bucket],
       AiCertification::AssistantAndBackground::DECISION_LABELS.fetch(entry[:feature]), 'mapped guard probe']
    end
    write_csv('ai-cert-background-inventory.csv', %w[feature bucket decision trace_kind], rows)
  end

  def write_scenario_csv(rows)
    write_csv('ai-cert-background-scenarios.csv', %w[flow scenario expected actual reason result], rows)
  end

  def exclusion_reason(scenario)
    case scenario
    when 'success', 'provider_error', 'mid_call_exception', 'empty_response', 'malformed_or_duplicate_json', 'retry'
      'Provider stubs and result persistence differ by flow; no shared contract fixture asserts quota, reservation, and event deltas together.'
    when 'exhausted', 'no_flag_or_plan'
      'There is no uniform pre-provider reservation/gate; audited consumers include post-response counters and measurement-only calls.'
    when 'null_bucket'
      'NULL semantics differ by pool (response sharing versus unlimited internal); this flow lacks a shared reservation contract.'
    when 'concurrency'
      'Only reservation-owning consumers can enforce one-cup concurrency; most listed background calls have no reservation receipt.'
    end
  end

  def write_csv(filename, headers, rows)
    report_dir = Rails.root.join('tmp')
    FileUtils.mkdir_p(report_dir)
    CSV.open(report_dir.join(filename), 'w') do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end
end
