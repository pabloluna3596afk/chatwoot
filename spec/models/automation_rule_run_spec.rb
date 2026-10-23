require 'rails_helper'

RSpec.describe AutomationRuleRun do
  it 'rejects unknown outcomes' do
    run = build(:automation_rule_run, outcome: 'delivered')

    expect(run).not_to be_valid
  end

  it 'removes history when the rule is deleted, matching the neighboring pending table' do
    run = create(:automation_rule_run)
    run.automation_rule.destroy!

    expect(described_class.exists?(run.id)).to be(false)
  end
end
