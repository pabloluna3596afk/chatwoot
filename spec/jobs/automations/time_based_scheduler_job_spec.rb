require 'rails_helper'

RSpec.describe Automations::TimeBasedSchedulerJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:time_runner) { instance_double(Automations::TimeBasedRuleRunner, perform: true) }
  let(:contact_runner) { instance_double(Automations::ContactBasedRuleRunner, perform: true) }

  it 'runs active time and contact rules together by ascending ID without selecting other rules' do
    base_id = AutomationRule.maximum(:id).to_i + 1000
    rules = [2, 0, 1].map do |offset|
      schedule = if offset == 1
                   { kind: 'contact_date', date_source: 'last_activity', target_inbox_id: inbox.id }
                 else
                   { kind: 'hours_since_last_incoming', hours: 1 }
                 end
      create(:automation_rule, id: base_id + offset, account: account, event_name: 'time_triggered', schedule: schedule)
    end
    create(:automation_rule, account: account, event_name: 'time_triggered', active: false,
                             schedule: { kind: 'hours_since_last_incoming', hours: 1 })
    create(:automation_rule, account: account, event_name: 'conversation_created')
    allow(Automations::TimeBasedRuleRunner).to receive(:new).and_return(time_runner)
    allow(Automations::ContactBasedRuleRunner).to receive(:new).and_return(contact_runner)
    expect(Automations::TimeBasedRuleRunner).to receive(:new).with(rules[1]).ordered
    expect(Automations::ContactBasedRuleRunner).to receive(:new).with(rules[2]).ordered
    expect(Automations::TimeBasedRuleRunner).to receive(:new).with(rules[0]).ordered

    job.perform

    expect(time_runner).to have_received(:perform).twice
    expect(contact_runner).to have_received(:perform).once
  end
end
