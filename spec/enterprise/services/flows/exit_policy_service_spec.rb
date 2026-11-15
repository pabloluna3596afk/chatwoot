require 'rails_helper'

RSpec.describe Flows::ExitPolicyService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:flow) do
    Flow.create!(account: account, name: 'Pending exit', exit_policy: {
                   on_complete: { status: 'pending', assignee_mode: 'agent', agent_id: agent.id }
                 })
  end
  let(:run) { FlowRun.create!(account: account, conversation: conversation, flow: flow) }

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    create(:inbox_member, inbox: inbox, user: agent)
    conversation.update!(assignee: nil, ai_assignee: nil)
  end

  it 'preserves a pending exit policy when assigning a person in a Captain inbox' do
    described_class.new(run: run, event: :on_complete).perform

    expect(conversation.reload).to have_attributes(status: 'pending', assignee: agent)
    expect(run.reload.state).to eq('completed')
  end
end
