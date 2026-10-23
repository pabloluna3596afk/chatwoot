require 'rails_helper'

RSpec.describe AutomationRules::PurgeRunsJob do
  it 'purges only runs strictly older than thirty days' do
    freeze_time do
      old_run = create(:automation_rule_run, created_at: 30.days.ago - 1.second)
      boundary_run = create(:automation_rule_run, created_at: 30.days.ago)
      recent_run = create(:automation_rule_run)

      described_class.perform_now

      expect(AutomationRuleRun.exists?(old_run.id)).to be(false)
      expect(AutomationRuleRun.where(id: [boundary_run.id, recent_run.id]).count).to eq(2)
    end
  end
end
