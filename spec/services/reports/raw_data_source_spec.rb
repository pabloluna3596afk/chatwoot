require 'rails_helper'

RSpec.describe Reports::RawDataSource do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:since_time) { Time.utc(2026, 10, 5) }
  let(:until_time) { Time.utc(2026, 10, 12) }
  let(:source) do
    described_class.new(account: account, metric: 'resolutions_count', scope: account, dimension_type: 'agent',
                        range: since_time...until_time, group_by: 'day', timezone_offset: 0, business_hours: false)
  end

  before do
    2.times do
      conversation = create(:conversation, account: account, inbox: inbox, assignee: user, created_at: since_time - 30.days)
      2.times do
        create(:reporting_event, account: account, conversation: conversation, inbox: inbox, user: user,
                                 name: 'conversation_resolved', created_at: since_time + 1.hour)
      end
      create(:reporting_event, account: account, conversation: conversation, inbox: inbox, user: user,
                               name: 'conversation_resolved', created_at: since_time - 1.second)
    end
  end

  it 'keeps counting four resolution events for normal reports, independent of conversation creation dates' do
    expect(source.aggregate).to eq(4)
    expect(source.timeseries.sum { |point| point[:value] }).to eq(4)
  end

  it 'keeps counting resolution events in normal report summaries' do
    expect(source.summary[user.id][:conversations_count]).to eq(0)
    expect(source.summary[user.id][:resolved_conversations_count]).to eq(4)
  end
end
