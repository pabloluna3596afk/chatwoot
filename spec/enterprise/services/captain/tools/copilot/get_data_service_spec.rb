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

  it 'explains that conversation records should be retrieved with search_conversation' do
    expect(service.description).to include('use search_conversation to retrieve conversation records')
    expect(service.execute(resource: 'unknown', filters: {})).to include(error: /get_data returns counts only; use search_conversation/)
  end

  it 'returns clear validation errors and enforces a per-turn call limit' do
    expect(service.execute(resource: 'unknown', filters: {})).to include(error: /Unknown resource/)
    Captain::Copilot::CollectionService::MAX_TOOL_CALLS.times do
      service.execute(resource: 'conversations', filters: {})
    end

    expect(service.execute(resource: 'conversations', filters: {})).to include(error: /at most 5 calls per turn/)
  end

  it 'filters conversations by explicit dates and supports daily and weekly groupings' do
    create(:conversation, account: account, created_at: 2.days.ago, last_activity_at: 2.days.ago)
    create(:conversation, account: account, created_at: 1.day.ago, last_activity_at: 1.day.ago)
    recent = create(:conversation, account: account, created_at: Time.current, last_activity_at: Time.current)
    filters = { created_after: 1.day.ago.beginning_of_day.iso8601 }

    result = service.execute(resource: 'conversations', filters: filters, group_by: 'day')
    weekly = service.execute(resource: 'conversations', filters: filters, group_by: 'week')

    expect(result[:total]).to eq(2), result.inspect
    expect(result[:groups]).not_to be_empty
    expect(weekly[:group_by]).to eq('week')
    expect(recent).to be_persisted
  end

  it 'rejects invalid date ranges and preserves legacy relative range filters' do
    invalid = service.execute(resource: 'conversations', filters: { created_after: 'bad-value' })
    legacy = service.execute(resource: 'conversations', filters: { relative_range: 'last_7_days' })

    expect(invalid).to include(error: /date filters/)
    expect(legacy[:total]).to be >= 0
  end

  it 'supports current-agent and unassigned counts in conversation filters' do
    create(:conversation, account: account, assignee: user)
    create(:conversation, account: account)

    mine = service.execute(resource: 'conversations', filters: { assignee_id: 'me' })
    unassigned = service.execute(resource: 'conversations', filters: { assignee_id: 'unassigned' })

    expect(mine[:total]).to eq(1)
    expect(unassigned[:total]).to eq(1)
  end
end
