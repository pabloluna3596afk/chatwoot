require 'rails_helper'

RSpec.describe AutomationRules::RunRecorder do
  let(:rule) { create(:automation_rule) }
  let(:conversation) { create(:conversation, account: rule.account) }

  it 'records the rule, account, event and contact without customer content' do
    described_class.record(rule: rule, outcome: 'executed', conversation: conversation, details: { actions: [] })

    expect(rule.runs.sole.attributes).to include('account_id' => rule.account_id, 'event_name' => rule.event_name,
                                                 'contact_id' => conversation.contact_id, 'details' => { 'actions' => [] })
  end

  it 'absorbs database errors and logs only the error class' do
    rule
    allow(AutomationRuleRun).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'private customer data')
    allow(Rails.logger).to receive(:error)

    expect { described_class.record(rule: rule, outcome: 'executed') }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with('[AutomationRules::RunRecorder] record failed: ActiveRecord::StatementInvalid')
    expect(rule.runs.count).to eq(0)
  end

  it 'caps executions, increments the last row counter and still records failures' do
    stub_const('AutomationRules::RunRecorder::DAILY_LIMIT', 2)
    4.times { described_class.record(rule: rule, outcome: 'executed') }

    expect(rule.runs.count).to eq(2)
    expect(rule.runs.order(:id).last.details).to eq('suppressed_executed_count' => 2)

    described_class.record(rule: rule, outcome: 'failed', reason: 'action_error')
    expect(rule.runs.where(outcome: 'failed').count).to eq(1)
  end

  it 'starts a new daily allowance and keeps rules independent' do
    stub_const('AutomationRules::RunRecorder::DAILY_LIMIT', 1)
    create(:automation_rule_run, automation_rule: rule, created_at: 1.day.ago)
    other_rule = create(:automation_rule, account: rule.account)
    described_class.record(rule: rule, outcome: 'executed')
    described_class.record(rule: other_rule, outcome: 'executed')

    expect(rule.runs.count).to eq(2)
    expect(other_rule.runs.count).to eq(1)
  end
end
