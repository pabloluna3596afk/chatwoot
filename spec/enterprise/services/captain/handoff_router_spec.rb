require 'rails_helper'

RSpec.describe Captain::HandoffRouter do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, status: :pending) }
  let(:agent) { create(:user, account: account) }
  let(:team) { create(:team, account: account) }

  before do
    account.enable_features!('captain_integration')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    create(:inbox_member, inbox: inbox, user: agent)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(agent.id.to_s => 'online')
  end

  it 'plans the defaults without writing anything or adding a note' do
    expect(conversation).not_to receive(:save)
    expect(described_class.new(conversation: conversation, assistant: assistant).plan).to have_attributes(
      kind: :new, assignee: nil, team: nil, priority: nil, note: nil
    )
  end

  %w[new reopened].each do |kind|
    context "with #{kind} routing" do
      before do
        if kind == 'reopened'
          conversation.update!(additional_attributes: { 'captain_reopened_at' => '2026-11-18T12:00:00Z',
                                                        'captain_previous_assignee_id' => agent.id })
        end
        create(:conversation, account: account, inbox: inbox, contact: conversation.contact, assignee: agent)
        assistant.update!(config: assistant.config.merge('handoff_routing' => { kind => { 'mode' => 'last_agent' } }))
      end

      it 'uses the previous online inbox member' do
        expect(described_class.new(conversation: conversation, assistant: assistant).plan.assignee).to eq(agent)
      end

      it 'falls back when offline' do
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return(agent.id.to_s => 'offline')
        expect(described_class.new(conversation: conversation, assistant: assistant).plan.assignee).to be_nil
      end

      it 'falls back when over capacity' do
        allow(inbox).to receive(:member_ids_with_assignment_capacity).and_return([])
        expect(described_class.new(conversation: conversation, assistant: assistant).plan.assignee).to be_nil
      end

      it 'falls back when the person left the inbox' do
        inbox.inbox_members.destroy_all
        expect(described_class.new(conversation: conversation, assistant: assistant).plan.assignee).to be_nil
      end
    end
  end

  it 'does not borrow a previous agent from another inbox' do
    create(:conversation, account: account, contact: conversation.contact, assignee: agent)
    assistant.update!(config: assistant.config.merge('handoff_routing' => { 'new' => { 'mode' => 'last_agent' } }))
    expect(described_class.new(conversation: conversation, assistant: assistant).plan.assignee).to be_nil
  end

  team_modes = %w[team ai_team]
  %w[new reopened].each do |kind|
    team_modes.each do |mode|
      context "with #{kind} #{mode}" do
        before do
          create(:team_member, team: team, user: agent)
          conversation.update!(additional_attributes: { 'captain_reopened_at' => '2026-11-18T12:00:00Z' }) if kind == 'reopened'
          row = { 'mode' => mode }
          row['team_id'] = team.id if mode == 'team'
          assistant.update!(config: assistant.config.merge('handoff_routing' => { kind => row }))
        end

        it 'selects an eligible team and lets existing assignment resolve the person' do
          routing = described_class.new(conversation: conversation, assistant: assistant, team_name: team.name).plan
          expect(routing).to have_attributes(team: team, assignee: nil)
          conversation.bot_handoff!(routing: routing)
          expect(conversation.reload).to have_attributes(status: 'open', team: team, assignee: agent)
          expect(routing.note).to include(team.name, agent.name)
        end

        it 'leaves the team unassigned if nobody is online' do
          allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
          routing = described_class.new(conversation: conversation, assistant: assistant, team_name: team.name).plan
          conversation.bot_handoff!(routing: routing)
          expect(conversation.reload).to have_attributes(team: team, assignee: nil)
          expect(routing.note).to include(I18n.t('captain.notes.handoff_routing.team_unassigned', team: team.name))
        end

        it 'does not assign a team member over capacity' do
          allow(inbox).to receive(:member_ids_with_assignment_capacity).and_return([])
          routing = described_class.new(conversation: conversation, assistant: assistant, team_name: team.name).plan
          conversation.bot_handoff!(routing: routing)
          expect(conversation.reload).to have_attributes(team: team, assignee: nil)
        end

        it 'assigns within the same team even when inbox auto assignment is disabled' do
          conversation.update!(team: team, assignee: nil)
          routing = described_class.new(conversation: conversation, assistant: assistant, team_name: team.name).plan
          conversation.bot_handoff!(routing: routing)
          expect(conversation.reload).to have_attributes(team: team, assignee: agent)
        end

        it 'rejects a team without inbox members' do
          inbox.inbox_members.destroy_all
          expect(described_class.new(conversation: conversation, assistant: assistant, team_name: team.name).plan.team).to be_nil
        end

        it 'rejects a team with auto assignment disabled' do
          team.update!(allow_auto_assign: false)
          expect(described_class.new(conversation: conversation, assistant: assistant, team_name: team.name).plan.team).to be_nil
        end
      end
    end
  end

  it 'logs and ignores an invented AI team' do
    assistant.update!(config: assistant.config.merge('handoff_routing' => { 'new' => { 'mode' => 'ai_team' } }))
    conversation
    allow(Rails.logger).to receive(:info).and_call_original
    expect(Rails.logger).to receive(:info).with(/team_rejected.*Invented/)
    expect(described_class.new(conversation: conversation, assistant: assistant, team_name: 'Invented').plan.team).to be_nil
  end

  it 'falls back if the saved fixed team was deleted' do
    assistant.update!(config: assistant.config.merge('handoff_routing' => { 'new' => { 'mode' => 'team', 'team_id' => team.id } }))
    team.destroy!
    expect(described_class.new(conversation: conversation, assistant: assistant).plan.team).to be_nil
  end

  signals = [nil, false, true, 'true']
  %w[off on_signal always].each do |policy|
    signals.each do |signal|
      it "handles priority #{policy} with signal #{signal.inspect}" do
        assistant.update!(config: assistant.config.merge('handoff_priority' => policy))
        routing = described_class.new(conversation: conversation, assistant: assistant, urgent: signal).plan
        expected = policy == 'always' || (policy == 'on_signal' && signal == true) ? :high : nil
        expect(routing.priority).to eq(expected)
      end
    end
  end

  it 'never lowers urgent priority or appends a misleading high note' do
    assistant.update!(config: assistant.config.merge('handoff_priority' => 'always'))
    conversation.update!(priority: :urgent)
    routing = described_class.new(conversation: conversation, assistant: assistant).plan
    conversation.bot_handoff!(routing: routing)
    expect(conversation.reload).to be_urgent
    expect(routing.note).to be_nil
  end
end
