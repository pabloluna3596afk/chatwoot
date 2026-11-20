require 'rails_helper'

RSpec.describe Captain::PurgeDecisionsJob do
  it 'purges in batches by occurred_at, preserves the boundary, and nullifies retained child links' do
    travel_to Time.current.change(usec: 0) do
      old = create(:captain_decision, occurred_at: 90.days.ago - 1.second)
      child = create(:captain_decision, account: old.account, conversation: old.conversation, assistant: old.assistant, parent_decision: old,
                                        occurred_at: 90.days.ago)
      recent = create(:captain_decision)
      described_class.perform_now
      expect(Captain::Decision.exists?(old.id)).to be(false)
      expect(child.reload.parent_decision_id).to be_nil
      expect(Captain::Decision.exists?(recent.id)).to be(true)
    end
  end
end
