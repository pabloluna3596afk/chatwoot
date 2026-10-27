require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::ProposeActionService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }

  it 'creates at most three proposals per tool turn without executing them' do
    action_service = instance_double(Captain::Copilot::ActionItemService)
    allow(Captain::Copilot::ActionItemService).to receive(:new).with(thread: thread, user: user).and_return(action_service)
    pending_item = instance_double(CopilotActionItem, status: 'pending')
    allow(action_service).to receive(:propose).and_return(pending_item)
    tool = described_class.new(assistant, copilot_thread: thread, user: user)

    3.times do
      expect(tool.execute(action: 'add_label', target: { 'type' => 'Contact', 'id' => 1 }, payload: { 'label_id' => 1 }))
        .to include(status: 'pending')
    end
    expect(tool.execute(action: 'add_label', target: { 'type' => 'Contact', 'id' => 1 }, payload: { 'label_id' => 1 }))
      .to include(error: 'At most three proposals are allowed per turn')
    expect(action_service).to have_received(:propose).exactly(3).times
  end
end
