require 'rails_helper'

RSpec.describe Captain::Llm::ContactAttributesService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, conversation) }

  before { put_account_on_plan(account, captain_internal_calls: 1) }

  it 'reserves and consumes one internal call for successful attribute generation' do
    allow(service).to receive(:generate_attributes).and_return([])
    expect(account).to receive(:reserve_captain_ai_usage!).with(bucket: :internal, reservation_id: anything).and_return(true)
    expect(account).to receive(:finish_captain_ai_usage!).with(bucket: :internal, reservation_id: anything).and_return(true)

    service.generate_and_update_attributes
  end

  it 'skips attribute generation when the internal allowance is exhausted' do
    allow(account).to receive(:reserve_captain_ai_usage!).and_return(false)
    expect(service).not_to receive(:generate_attributes)

    expect(service.generate_and_update_attributes).to be_nil
  end

  it 'releases the reservation when attribute generation fails' do
    allow(service).to receive(:generate_attributes).and_raise(IOError, 'provider unavailable')
    expect(account).to receive(:reserve_captain_ai_usage!).with(bucket: :internal, reservation_id: anything).and_return(true)
    expect(account).to receive(:release_captain_ai_usage!).with(bucket: :internal, reservation_id: anything).and_return(true)
    expect(account).not_to receive(:finish_captain_ai_usage!)

    expect { service.generate_and_update_attributes }.to raise_error(IOError, 'provider unavailable')
  end
end
