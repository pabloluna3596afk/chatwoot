require 'rails_helper'

RSpec.describe Captain::AssistantMigration::InstructionAuditor do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) do
    described_class.new(
      assistant: assistant, source_payload: {}, draft: {},
      available_additions: { response_guidelines: 0, guardrails: 0, scenario_candidates: 0,
                             faq_document_candidates: 0, needs_review: 0 }
    )
  end

  before do
    put_account_on_plan(account, captain_internal_calls: 1)
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
  end

  it 'reserves and consumes one internal call for a successful audit' do
    allow(service).to receive(:make_api_call).and_return(message: { guardrails: ['Keep customer data private.'] })

    expect { service.perform }.to change { account.reload.current_usage_period.internal_calls_consumed }.by(1)
  end

  it 'releases the internal reservation when the provider returns an error' do
    allow(service).to receive(:make_api_call).and_return(error: 'provider unavailable')

    expect { service.perform }.not_to(change { account.reload.current_usage_period.internal_calls_consumed })
  end

  it 'does not call the provider when the internal allowance is exhausted' do
    account.current_usage_period.update!(internal_calls_consumed: 1)
    expect(service).not_to receive(:make_api_call)

    expect(service.perform).to include(error_code: 429)
  end
end
