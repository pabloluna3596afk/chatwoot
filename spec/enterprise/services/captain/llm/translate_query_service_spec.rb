require 'rails_helper'

RSpec.describe Captain::Llm::TranslateQueryService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    put_account_on_plan(account, captain_internal_calls: 1)
    allow(service).to receive(:query_in_target_language?).and_return(false)
  end

  it 'charges one internal action for a translated knowledge query' do
    allow(service).to receive(:make_api_call).and_return(message: 'Bonjour')

    expect(service.translate('Hello', target_language: 'French')).to eq('Bonjour')
    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(1)
    expect(account.current_usage_period.responses_consumed).to eq(0)
  end

  it 'keeps the original query without calling the provider when quota is exhausted' do
    account.current_usage_period.update!(internal_calls_consumed: 1)
    expect(service).not_to receive(:make_api_call)

    expect(service.translate('Hello', target_language: 'French')).to eq('Hello')
  end

  it 'releases the reservation when the underlying task reports a provider failure' do
    allow(service).to receive(:make_api_call).and_return(error: 'Provider unavailable')

    expect(service.translate('Hello', target_language: 'French')).to eq('Hello')
    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(0)
    expect(AiUsageReservation.where(account_plan_usage: account.current_usage_period).where.not(released_at: nil).count).to eq(1)
  end
end
