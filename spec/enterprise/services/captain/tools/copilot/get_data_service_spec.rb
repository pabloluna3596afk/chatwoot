require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::GetDataService do
  let(:account) { create(:account) }
  let(:user) { create(:user, role: 'administrator', account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  it 'registers the get_data name and typed parameters' do
    expect(service.name).to eq('get_data')
    expect(service.parameters_schema.fetch('properties').keys).to contain_exactly('resource', 'filters', 'group_by', 'aggregate')
  end

  it 'returns clear validation errors and enforces a per-turn call limit' do
    expect(service.execute(resource: 'unknown', filters: {})).to include(error: /Unknown resource/)
    Captain::Copilot::CollectionService::MAX_TOOL_CALLS.times do
      service.execute(resource: 'conversations', filters: {})
    end

    expect(service.execute(resource: 'conversations', filters: {})).to include(error: /at most 5 calls per turn/)
  end
end
