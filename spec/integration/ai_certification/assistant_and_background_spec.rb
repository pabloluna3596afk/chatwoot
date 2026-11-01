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
    { name: 'assistant V1 response (delivery stubbed)', feature: 'assistant', bucket: :captain_responses,
      decision: :measure_and_limit, contract: :llm },
    { name: 'assistant V2 response (delivery stubbed)', feature: 'captain_reply', bucket: :captain_responses,
      decision: :measure_and_limit, contract: :llm },
    { name: 'action classifier', feature: 'assistant_action_classifier', bucket: :internal,
      decision: :measure_and_limit, contract: :llm },
    { name: 'auto-resolve evaluator', feature: 'content_evaluator', bucket: :internal,
      decision: :measure_only, contract: :moderation },
    { name: 'playground', feature: 'assistant_playground', bucket: :captain_responses,
      decision: :measure_and_limit, contract: :llm },
    { name: 'FAQ and documents', feature: 'document_faq_generation', bucket: :captain_responses,
      decision: :measure_only, contract: :llm },
    { name: 'embeddings and moderation', feature: 'embedding', bucket: :internal,
      decision: :measure_only, contract: :embedding },
    { name: 'audio transcription', feature: 'audio_transcription', bucket: :captain_responses,
      decision: :measure_and_limit, contract: :audio },
    { name: 'legacy Integrations::LlmBaseService', feature: 'captain_reply', bucket: :captain_responses,
      decision: :measure_and_limit, contract: :llm }
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

RSpec.shared_examples 'a metered provider-flow contract' do |flow, scenario|
  it "executes #{flow[:name]} / #{scenario}" do
    result = execute_flow_contract(flow, scenario)
    record_scenario(flow, scenario, result)
    expect(%w[PASS EXCLUDED]).to include(result[:result]), result[:reason]
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

  AiCertification::AssistantAndBackground::FLOWS.each do |flow|
    AiCertification::AssistantAndBackground::SCENARIOS.each do |scenario|
      it_behaves_like 'a metered provider-flow contract', flow, scenario
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

  def execute_flow_contract(flow, scenario)
    account = create(:account)
    limited = flow[:decision] == :measure_and_limit
    exclusion = scenario_exclusion(flow, scenario, limited)
    return exclusion if exclusion

    configure_flow_account(account, flow, null_bucket: scenario == 'null_bucket') if limited
    state = flow_state(account, flow, scenario, limited)

    if %w[exhausted no_flag_or_plan].include?(scenario) && limited
      reason = run_denial_contract(account, flow, scenario, state[:provider_calls])
      return result_row('PASS', 'provider not called; no usage event or bucket change', reason)
    end

    actual = run_provider_scenario(flow, scenario, state)
    finish_contract_reservation(account, flow, state[:reservation_id], scenario, state[:reserved])
    contract_result(flow, scenario, state, actual, limited)
  rescue StandardError => e
    result_row('FAIL', 'provider contract completes with expected lifecycle', "#{e.class}: #{e.message}")
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def scenario_exclusion(flow, scenario, limited)
    # These rows are intentionally excluded for every quota-limited response flow: Plan.monthly_messages is NOT NULL,
    # so captain_responses cannot exercise NULL-as-unlimited. NULL sharing is a Copilot-specific bucket contract.
    if scenario == 'null_bucket' && limited && flow[:bucket] == :captain_responses
      return result_row('EXCLUDED', 'response pool cannot be NULL on a plan',
                        'Plan.monthly_messages is NOT NULL; NULL semantics apply to Copilot sharing or internal unlimited usage.')
    end
    # These rows are excluded only for measure_only services. Entitlement has no quota gate to exhaust or disable,
    # and no reservation receipt exists to race for a final credit; adding a quota would change their billing contract.
    if %w[exhausted no_flag_or_plan].include?(scenario) && !limited
      return result_row('EXCLUDED', 'scenario requires a quota-enforced flow',
                        "#{flow[:feature]} is measure_only; it has no quota gate to exhaust or disable.")
    end
    if scenario == 'concurrency' && !limited
      return result_row('EXCLUDED', 'one-cup concurrency contract',
                        "#{flow[:feature]} is measure_only and creates no reservation receipt, so it cannot race for a quota cup.")
    end
    # These rows ask for JSON normalization from consumers whose public service result is text, vector, audio, or a
    # moderation decision. Parsing JSON here would test a different contract and could corrupt the consumer output.
    if scenario == 'malformed_or_duplicate_json' && !json_flow?(flow)
      return result_row('EXCLUDED', 'provider response contract',
                        "#{flow[:feature]} consumes unstructured text, vectors, audio, or moderation output; " \
                        'JSON parsing is not part of this flow.')
    end
    # EmbeddingService treats blank input as a local no-op and returns [] before opening UsageContext or calling the
    # provider. There is no provider-produced empty response to meter for this service contract.
    return unless scenario == 'empty_response' && flow[:contract] == :embedding

    result_row('EXCLUDED', 'embedding input contract',
               'EmbeddingService returns [] before contacting the provider when input content is blank; ' \
               'it has no semantic empty-text response.')
  end

  def flow_state(account, flow, scenario, limited)
    state = {
      account: account, bucket_before: usage_count(account, flow[:bucket]),
      events_before: AiUsageEvent.where(account: account).count,
      reservations_before: AiUsageReservation.joins(:account_plan_usage)
                                             .where(account_plan_usages: { account_id: account.id }).count,
      provider_calls: 0, reservation_id: SecureRandom.uuid, limited: limited
    }
    state[:reserved] = limited && scenario != 'no_flag_or_plan' &&
                       account.reserve_captain_ai_usage!(bucket: flow[:bucket], reservation_id: state[:reservation_id])
    state[:reservation_required] = state[:reserved] &&
                                   AiUsageReservation.exists?(reservation_id: state[:reservation_id])
    state
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/AbcSize
  def run_provider_scenario(flow, scenario, state)
    account = state[:account]
    if scenario == 'retry'
      invoke_stubbed_provider(flow, 'mid_call_exception', account, state[:reservation_id], state[:reservation_required]) do
        state[:provider_calls] += 1
      end
      account.release_captain_ai_usage!(bucket: flow[:bucket], reservation_id: state[:reservation_id]) if state[:reserved]
      state[:reservation_id] = SecureRandom.uuid
      state[:reserved] = account.reserve_captain_ai_usage!(bucket: flow[:bucket], reservation_id: state[:reservation_id]) if state[:reserved]
      state[:reservation_required] = state[:reserved] && AiUsageReservation.exists?(reservation_id: state[:reservation_id])
      return invoke_stubbed_provider(flow, 'success', account, state[:reservation_id], state[:reservation_required]) do
        state[:provider_calls] += 1
      end
    end
    expect(account.reserve_captain_ai_usage!(bucket: flow[:bucket])).to be(false) if scenario == 'concurrency'
    invoke_stubbed_provider(flow, scenario, account, state[:reservation_id], state[:reservation_required]) do
      state[:provider_calls] += 1
    end
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def contract_result(flow, scenario, state, actual, limited)
    account = state[:account]
    event = AiUsageEvent.where(account: account).order(:id).last
    expected_status = %w[provider_error mid_call_exception].include?(scenario) ? 'error' : 'ok'
    valid = state[:provider_calls] == (scenario == 'retry' ? 2 : 1)
    valid &&= event&.feature == flow[:feature] && event&.bucket == flow[:bucket].to_s && event&.status == expected_status
    valid &&= event_count(account) == state[:events_before] + (scenario == 'retry' ? 2 : 1)
    valid &&= reservation_count(account) == state[:reservations_before] unless limited
    valid &&= usage_count(account, flow[:bucket]) == state[:bucket_before] + expected_bucket_delta(flow, scenario, limited)
    valid &&= reservation_state(account, state[:reservation_id]) == 'released' if limited && failed_attempt?(scenario)
    if state[:reserved] && %w[success retry concurrency].include?(scenario)
      valid &&= reservation_state(account, state[:reservation_id]) == 'consumed/absent'
    end
    valid &&= actual == scenario_result(scenario) if %w[empty_response provider_error mid_call_exception].include?(scenario)
    result_row(valid ? 'PASS' : 'FAIL', 'stubbed provider call, event, receipt, and bucket deltas match',
               "calls=#{state[:provider_calls]}; event=#{event&.status}/#{event&.feature}/#{event&.bucket}; " \
               "bucket_delta=#{usage_count(account, flow[:bucket]) - state[:bucket_before]}; " \
               "receipt=#{reservation_state(account, state[:reservation_id])}")
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def expected_bucket_delta(flow, scenario, limited)
    return 0 unless limited && %w[provider_error mid_call_exception empty_response].exclude?(scenario)
    return 0 if scenario == 'null_bucket' && flow[:bucket] == :internal

    1
  end

  def event_count(account)
    AiUsageEvent.where(account: account).count
  end

  def reservation_count(account)
    AiUsageReservation.joins(:account_plan_usage).where(account_plan_usages: { account_id: account.id }).count
  end

  def failed_attempt?(scenario)
    %w[provider_error mid_call_exception empty_response].include?(scenario)
  end

  def scenario_result(scenario)
    { 'empty_response' => :empty, 'provider_error' => :provider_error,
      'mid_call_exception' => :mid_call_exception }.fetch(scenario)
  end

  def configure_flow_account(account, flow, null_bucket: false)
    bucket_limit_key = { internal: :captain_internal_calls, copilot: :captain_copilot_responses,
                         captain_responses: :monthly_messages }.fetch(flow[:bucket])
    put_account_on_plan(account, **{ bucket_limit_key => (null_bucket ? nil : 1) })
    allow(account).to receive(:feature_enabled?).and_return(true)
  end

  def run_denial_contract(account, flow, scenario, provider_calls)
    if scenario == 'exhausted'
      # The single configured cup was already consumed above; an additional
      # reservation must be rejected before any provider code can run.
      expect(account.reserve_captain_ai_usage!(bucket: flow[:bucket])).to be(false)
    else
      allow(account).to receive(:feature_enabled?).and_return(false)
      expect(Llm::Entitlement.new(account: account, feature: flow[:feature]).call[:reason]).to eq(:feature_disabled)
    end
    expect(provider_calls).to eq(0)
    expect(AiUsageEvent.where(account: account)).to be_empty
    'entitlement/reservation rejected before provider invocation'
  end

  # rubocop:disable Metrics/MethodLength
  def invoke_stubbed_provider(flow, scenario, account, reservation_id, limited)
    caller = Class.new { include Integrations::LlmInstrumentation }.new
    params = { account: account, feature_name: flow[:feature], bucket: flow[:bucket],
               model: 'gpt-test', provider: 'openai', span_name: 'ai.certification.contract' }
    provider = lambda do
      yield
      case scenario
      when 'provider_error' then raise IOError, 'stubbed provider error'
      when 'mid_call_exception' then raise ArgumentError, 'stubbed mid-call failure'
      when 'empty_response' then nil
      when 'malformed_or_duplicate_json' then '{"action":"handoff","action":"reply"}'
      else { 'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 } }
      end
    end
    Llm::UsageContext.with(
      account: account, bucket: flow[:bucket], feature: flow[:feature], reservation_id: reservation_id,
      context: { reservation_required: limited }
    ) { instrumented_provider_call(caller, flow, params, &provider) }
  rescue IOError
    :provider_error
  rescue ArgumentError => e
    raise unless e.message == 'stubbed mid-call failure'

    :mid_call_exception
  end

  def instrumented_provider_call(caller, flow, params, &)
    result = case flow[:contract]
             when :embedding then caller.instrument_embedding_call(params, &)
             when :moderation then caller.instrument_moderation_call(params, &)
             when :audio
               caller.send(:with_usage_recording, params) do
                 caller.instrument_audio_transcription(params, &)
               end
             else
               caller.send(:with_usage_recording, params) do
                 caller.instrument_llm_call(params, &)
               end
             end
    result.nil? ? :empty : result
  end
  # rubocop:enable Metrics/MethodLength

  def finish_contract_reservation(account, flow, reservation_id, scenario, reserved)
    return unless reserved

    if %w[provider_error mid_call_exception empty_response].include?(scenario)
      account.release_captain_ai_usage!(bucket: flow[:bucket], reservation_id: reservation_id)
    else
      account.finish_captain_ai_usage!(bucket: flow[:bucket], reservation_id: reservation_id)
    end
  end

  def usage_count(account, bucket)
    limits = account.reload.usage_limits.dig(:captain, bucket == :captain_responses ? :responses : bucket)
    limits[:consumed].to_i
  end

  def reservation_state(account, reservation_id)
    reservation = AiUsageReservation.joins(:account_plan_usage).find_by(
      reservation_id: reservation_id, account_plan_usages: { account_id: account.id }
    )
    reservation&.released_at ? 'released' : 'consumed/absent'
  end

  def json_flow?(flow)
    %w[assistant_action_classifier document_faq_generation].include?(flow[:feature])
  end

  def result_row(result, expected, actual, reason = nil)
    { result: result, expected: expected, actual: actual, reason: reason }
  end

  def record_scenario(flow, scenario, result)
    rows = Thread.current[:ai_cert_background_scenario_rows] ||= []
    rows << [flow[:name], scenario, result[:expected], result[:actual], result[:reason], result[:result]]
    write_scenario_csv(rows)
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
