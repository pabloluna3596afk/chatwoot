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
    account.enable_features!('captain_integration')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    create(:inbox_member, inbox: inbox, user: agent)
    conversation.update!(assignee: nil, ai_assignee: nil)
  end

  it 'preserves a pending exit policy when assigning a person in a Captain inbox' do
    described_class.new(run: run, event: :on_complete).perform

    expect(conversation.reload).to have_attributes(status: 'pending', assignee: agent)
    expect(run.reload.state).to eq('completed')
  end

  it 'routes the Captain handoff before opening and adds the note to the existing summary' do
    flow.update!(exit_policy: { on_handoff: { status: 'open', assignee_mode: 'keep', private_note: true } })
    assistant.update!(config: assistant.config.merge('handoff_priority' => 'always'))
    conversation.update!(status: :pending, ai_assignee: assistant)
    expect(Captain::HandoffRouter).to receive(:new).with(conversation: conversation, assistant: assistant).and_call_original
    described_class.new(run: run, event: :on_handoff).perform
    expect(conversation.reload).to have_attributes(status: 'open', priority: 'high', ai_assignee: nil)
    expect(conversation.messages.where(private: true).sole.content).to end_with(I18n.t('captain.notes.handoff_routing.priority_high'))
  end

  it 'keeps the configured Captain team when the Flow policy clears assignment' do
    team = create(:team, account: account)
    create(:team_member, team: team, user: agent)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(agent.id.to_s => 'online')
    assistant.update!(config: { 'handoff_routing' => { 'new' => { 'mode' => 'team', 'team_id' => team.id } } })
    conversation.update!(status: :pending, ai_assignee: assistant)
    described_class.new(run: run, event: :on_handoff).perform
    expect(conversation.reload).to have_attributes(status: 'open', team: team, assignee: agent)
  end

  it 'applies priority even when the Flow assigns a person and opens the conversation' do
    flow.update!(exit_policy: { on_handoff: { status: 'open', assignee_mode: 'agent', agent_id: agent.id } })
    assistant.update!(config: { 'handoff_priority' => 'always' })
    conversation.update!(status: :pending, ai_assignee: assistant)
    described_class.new(run: run, event: :on_handoff).perform
    expect(conversation.reload).to have_attributes(status: 'open', priority: 'high', assignee: agent)
  end

  it 'does not route external bots' do
    flow.update!(exit_policy: { on_handoff: { status: 'open', assignee_mode: 'keep' } })
    conversation.update!(status: :pending, ai_assignee: create(:agent_bot, account: account))
    expect(Captain::HandoffRouter).not_to receive(:new)
    expect(conversation).to receive(:bot_handoff!).with(routing: nil).and_call_original
    described_class.new(run: run, event: :on_handoff).perform
  end
end
