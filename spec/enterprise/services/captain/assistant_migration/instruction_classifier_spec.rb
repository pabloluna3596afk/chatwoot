require 'rails_helper'

RSpec.describe Captain::AssistantMigration::InstructionClassifier do
  describe 'usage metering' do
    let(:account) { create(:account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:service) { described_class.new(assistant: assistant) }

    before do
      put_account_on_plan(account, captain_internal_calls: 2)
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
      allow(service).to receive(:make_api_call).and_return(message: {})
    end

    it 'charges one internal call for the classifier and one for its auditor' do
      auditor = Captain::AssistantMigration::InstructionAuditor.new(
        assistant: assistant, source_payload: {}, draft: {},
        available_additions: { response_guidelines: 0, guardrails: 0, scenario_candidates: 0,
                               faq_document_candidates: 0, needs_review: 0 }
      )
      allow(auditor).to receive(:make_api_call).and_return(message: { guardrails: ['Keep customer data private.'] })
      allow(Captain::AssistantMigration::InstructionAuditor).to receive(:new).and_return(auditor)

      expect { service.perform }.to change { account.reload.current_usage_period.internal_calls_consumed }.by(2)
    end
  end

  describe Captain::AssistantMigration::InstructionClassifierSchema do
    it 'does not request classification notes' do
      expect(described_class.as_json.to_s).not_to include('classification_notes')
    end
  end

  describe 'classifier prompt' do
    it 'keeps the model focused on active behavior and approved FAQ candidates' do
      prompt = Captain::PromptRenderer.render('instruction_classifier')

      expect(prompt).to include(
        'The original custom instructions remain stored unchanged',
        'A FAQ cannot implicitly preserve an action',
        'Scenario candidates remain pending metadata',
        'Convert reusable query-dependent facts into natural customer questions',
        'an error code that requires immediate',
        'actively require specialist-name verification',
        'Mandatory prohibitions are not FAQ-only',
        'never promise refunds after 30 days',
        'never recommend cooking the product',
        'Treat explicit policy boundaries',
        'outside the stated condition, window, or exception',
        'source-defined behavior or workflow that requires an unavailable capability',
        'Do not require mandatory wording',
        'every mandatory action and prohibition remains active'
      )
    end
  end

  describe Captain::AssistantMigration::InstructionAuditorSchema do
    it 'only permits additions that fit in the generated draft' do
      schema = described_class.for(
        response_guidelines: 0,
        guardrails: 2,
        scenario_candidates: 1,
        faq_document_candidates: 3,
        needs_review: 4
      ).new.to_json_schema

      expect(schema['properties']).not_to have_key('response_guidelines')
      expect(schema.dig('properties', 'guardrails', 'maxItems')).to eq(2)
      expect(schema.dig('properties', 'scenario_candidates', 'maxItems')).to eq(1)
      expect(schema.dig('properties', 'faq_document_candidates', 'maxItems')).to eq(3)
      expect(schema.dig('properties', 'needs_review', 'maxItems')).to eq(4)
    end
  end

  describe 'auditor prompt' do
    it 'adds missing coverage without replacing the generated draft' do
      prompt = Captain::PromptRenderer.render('instruction_auditor')

      expect(prompt).to include(
        'This is a monotonic coverage audit',
        'Never repeat, rewrite, replace, or delete content',
        'If mandatory behavior appears only there, add the missing active guideline or guardrail',
        'available_additions gives the exact remaining capacity',
        'A needs_review item never replaces representable behavior',
        'No mandatory action or prohibition remains FAQ-only'
      )
    end
  end

  describe 'audited payload' do
    it 'appends a review note for an unavailable runtime capability' do
      service = described_class.new(assistant: instance_double(Captain::Assistant))
      generated_draft = {
        response_guidelines: [],
        guardrails: [],
        scenario_candidates: [],
        faq_document_candidates: [],
        needs_review: ['Existing conflict']
      }

      result = service.send(
        :audited_payload,
        generated_draft,
        { needs_review: ['Order-status lookup requires an unavailable account-history tool.'] }
      )

      expect(result[:needs_review]).to eq(
        ['Existing conflict', 'Order-status lookup requires an unavailable account-history tool.']
      )
    end
  end
end
