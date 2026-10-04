require 'rails_helper'

RSpec.describe Conversation, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:sla_policy).optional }
  end

  describe 'SLA policy updates' do
    let(:conversation) { create(:conversation) }
    let!(:sla_policy) { create(:sla_policy, account: conversation.account) }

    before do
      stub_request(:get, %r{\Ahttps://www\.gravatar\.com.*}).to_return(status: 404)
      stub_request(:get, %r{\Ahttps://www\.google\.com/s2/favicons.*}).to_return(status: 404)
    end

    it 'generates an activity message when the SLA policy is updated' do
      conversation.update!(sla_policy_id: sla_policy.id)

      perform_enqueued_jobs

      activity_message = conversation.messages.where(message_type: 'activity').last

      expect(activity_message).not_to be_nil
      expect(activity_message.message_type).to eq('activity')
      expect(activity_message.content).to include('added SLA policy')
    end

    # TODO: Reenable this when we let the SLA policy be removed from a conversation
    # it 'generates an activity message when the SLA policy is removed' do
    #   conversation.update!(sla_policy_id: sla_policy.id)
    #   conversation.update!(sla_policy_id: nil)

    #   perform_enqueued_jobs

    #   activity_message = conversation.messages.where(message_type: 'activity').last

    #   expect(activity_message).not_to be_nil
    #   expect(activity_message.message_type).to eq('activity')
    #   expect(activity_message.content).to include('removed SLA policy')
    # end
  end

  describe 'SLA completion' do
    let(:applied_sla) { create(:applied_sla) }
    let(:conversation) { applied_sla.conversation }

    it 'records the completion time when the conversation is resolved' do
      completion_time = Time.zone.parse('2026-07-15 10:00:00')

      travel_to(completion_time) { conversation.update!(status: :resolved) }

      expect(applied_sla.reload.completed_at).to eq(completion_time)
    end

    it 'records the completion time when SLA evaluation finishes during resolution' do
      completion_time = Time.zone.parse('2026-07-15 10:00:00')
      allow(conversation).to receive(:update_applied_sla_completion).and_wrap_original do |method|
        applied_sla.update!(sla_status: :missed)
        method.call
      end

      travel_to(completion_time) { conversation.update!(status: :resolved) }

      expect(applied_sla.reload).to have_attributes(sla_status: 'missed', completed_at: completion_time)
    end

    it 'clears the completion time when a nonterminal SLA is reopened' do
      conversation.update!(status: :resolved)

      conversation.update!(status: :open)

      expect(applied_sla.reload.completed_at).to be_nil
    end

    it 'preserves the completion time when a terminal SLA is reopened' do
      conversation.update!(status: :resolved)
      completed_at = applied_sla.reload.completed_at
      applied_sla.update!(sla_status: :missed)

      conversation.update!(status: :open)

      expect(applied_sla.reload.completed_at).to eq(completed_at)
    end
  end

  describe 'sla_policy' do
    let(:account) { create(:account) }
    let(:conversation) { create(:conversation, account: account) }
    let(:sla_policy) { create(:sla_policy, account: account) }
    let(:different_account_sla_policy) { create(:sla_policy) }

    context 'when sla_policy is getting updated' do
      it 'throws error if sla policy belongs to different account' do
        conversation.sla_policy = different_account_sla_policy
        expect(conversation.valid?).to be false
        expect(conversation.errors[:sla_policy]).to include('sla policy account mismatch')
      end

      it 'creates applied sla record if sla policy is present' do
        conversation.sla_policy = sla_policy
        conversation.save!
        expect(conversation.applied_sla.sla_policy_id).to eq(sla_policy.id)
      end

      it 'throws error if contact is blocked' do
        conversation.contact.update!(blocked: true)
        conversation.sla_policy = sla_policy

        expect(conversation.valid?).to be false
        expect(conversation.errors[:sla_policy]).to eq(['cannot be assigned to conversations with blocked contacts'])
      end

      it 'allows assigning sla after contact is unblocked' do
        conversation.contact.update!(blocked: true)
        conversation.contact.update!(blocked: false)
        conversation.sla_policy = sla_policy

        conversation.save!

        expect(conversation.applied_sla.sla_policy_id).to eq(sla_policy.id)
      end

      it 'keeps existing behavior when contact is missing' do
        conversation.update_columns(contact_id: nil, contact_inbox_id: nil) # rubocop:disable Rails/SkipsModelValidations

        expect(conversation.reload.sla_applicable?).to be true
      end
    end

    context 'when conversation already has a different sla' do
      before do
        conversation.update(sla_policy: create(:sla_policy, account: account))
      end

      it 'throws error if trying to assing a different sla' do
        conversation.sla_policy = sla_policy
        expect(conversation.valid?).to be false
        expect(conversation.errors[:sla_policy]).to eq(['conversation already has a different sla'])
      end

      it 'throws error if trying to set sla to nil' do
        conversation.sla_policy = nil
        expect(conversation.valid?).to be false
        expect(conversation.errors[:sla_policy]).to eq(['cannot remove sla policy from conversation'])
      end
    end
  end

  describe 'assignment capacity limits' do
    describe 'team assignment with inbox auto-assignment disabled' do
      let(:account) { create(:account) }
      let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false, auto_assignment_config: { max_assignment_limit: 1 }) }
      let(:team) { create(:team, account: account, allow_auto_assign: true) }
      let!(:agent1) { create(:user, account: account, role: :agent, auto_offline: false) }
      let!(:agent2) { create(:user, account: account, role: :agent, auto_offline: false) }

      before do
        create(:inbox_member, inbox: inbox, user: agent1)
        create(:inbox_member, inbox: inbox, user: agent2)
        create(:team_member, team: team, user: agent1)
        create(:team_member, team: team, user: agent2)
        # Both agents are over the limit (simulate by assigning open conversations)
        create_list(:conversation, 2, inbox: inbox, assignee: agent1, status: :open)
        create_list(:conversation, 2, inbox: inbox, assignee: agent2, status: :open)
      end

      it 'does not enforce max_assignment_limit for team assignment when inbox auto-assignment is disabled' do
        conversation = create(:conversation, inbox: inbox, account: account, assignee: nil, status: :open)

        # Assign to team to trigger the assignment logic
        conversation.update!(team: team)

        # Should assign to a team member even if they are over the limit
        expect(conversation.reload.assignee).to be_present
        expect([agent1, agent2]).to include(conversation.reload.assignee)
      end
    end
  end

  describe 'Captain ownership' do
    # Captain starts every new conversation of its inboxes as pending and owns it, whatever status is asked for, so the
    # status and the owner the scenario needs are set afterwards.
    def create_conversation(status:, ai_assignee: nil, **attributes)
      create(:conversation, status: status, **attributes).tap do |conversation|
        conversation.update_columns( # rubocop:disable Rails/SkipsModelValidations
          status: Conversation.statuses.fetch(status.to_s),
          ai_assignee_type: ai_assignee&.class&.name,
          assignee_agent_bot_id: ai_assignee&.id
        )
        conversation.reload
      end
    end
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:plain_inbox) { create(:inbox, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:assistant) { create(:captain_assistant, account: account) }

    before do
      create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    end

    describe '#captain_state' do
      it "is 'ai' for a pending conversation Captain owns" do
        conversation = create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant)

        expect(conversation.captain_state).to eq('ai')
      end

      it 'is nil for a pending conversation nobody owns, even in an inbox with an assistant' do
        conversation = create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: nil)
        conversation.update!(ai_assignee: nil)

        expect(conversation.captain_state).to be_nil
      end

      it 'is nil for a pending conversation in an inbox without an assistant' do
        conversation = create_conversation(account: account, inbox: plain_inbox, status: :pending)

        expect(conversation.captain_state).to be_nil
      end

      it 'is nil for a pending conversation owned by an agent bot' do
        agent_bot = create(:agent_bot, account: account)
        conversation = create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: agent_bot)

        expect(conversation.captain_state).to be_nil
      end

      it "is 'escalated' when Captain handed off and nobody took the conversation" do
        conversation = create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant)
        conversation.bot_handoff!

        expect(conversation.reload.captain_state).to eq('escalated')
      end

      it 'is nil after handoff when a human already owns the conversation' do
        conversation = create_conversation(account: account, inbox: inbox, status: :pending, assignee: agent)
        conversation.bot_handoff!

        expect(conversation.reload.captain_handed_off_at).to be_nil
        expect(conversation.ai_assignee).to be_nil
        expect(conversation.captain_state).to be_nil
      end

      it 'is nil for an open conversation that never went through Captain' do
        conversation = create_conversation(account: account, inbox: inbox, status: :open)

        expect(conversation.captain_state).to be_nil
      end
    end

    describe '#bot_handoff!' do
      it 'marks the handoff in the same save that opens the conversation and releases Captain as owner' do
        conversation = create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant)

        conversation.bot_handoff!

        expect(conversation.reload).to have_attributes(status: 'open', ai_assignee_type: nil, assignee_agent_bot_id: nil)
        expect(conversation.captain_handed_off_at).to be_present
      end

      it 'does not mark conversations Captain was not attending' do
        conversation = create_conversation(account: account, inbox: plain_inbox, status: :pending)

        conversation.bot_handoff!

        expect(conversation.reload.captain_handed_off_at).to be_nil
      end
    end

    describe 'clearing the handoff mark' do
      let(:conversation) do
        create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant).tap(&:bot_handoff!)
      end

      it 'clears it when an agent is assigned' do
        conversation.update!(assignee: agent)

        expect(conversation.reload.captain_handed_off_at).to be_nil
      end

      it 'clears it when the conversation is resolved' do
        conversation.update!(status: :resolved)

        expect(conversation.reload.captain_handed_off_at).to be_nil
      end

      it 'clears it when the conversation goes back to pending' do
        conversation.update!(status: :pending)

        expect(conversation.reload.captain_handed_off_at).to be_nil
      end

      it 'clears it when an agent hands the conversation back to Captain' do
        account.enable_features!('captain_integration')

        Conversations::AssignmentService.new(
          conversation: conversation, assignee_id: assistant.id, assignee_type: 'Captain::Assistant'
        ).perform

        expect(conversation.reload).to have_attributes(status: 'pending', captain_handed_off_at: nil, captain_state: 'ai')
        expect(conversation.ai_assignee).to eq(assistant)
      end

      it 'keeps it while the conversation stays open and unassigned' do
        conversation.update!(priority: :high)

        expect(conversation.reload.captain_handed_off_at).to be_present
      end
    end

    describe 'the status activity message' do
      def activity_content(conversation)
        have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: yield))
      end

      it 'says Captain is taking care of the conversation, not that it was marked pending' do
        conversation = create_conversation(account: account, inbox: inbox, status: :open)
        content = I18n.t('conversations.activity.status.captain_attending', assistant: assistant.name)

        expect { conversation.update!(status: :pending, ai_assignee: assistant) }.to activity_content(conversation) { content }
      end

      it 'says Captain handed the conversation over to the team' do
        conversation = create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant)
        content = I18n.t('conversations.activity.status.captain_handed_off', assistant: assistant.name)

        expect { conversation.bot_handoff! }.to activity_content(conversation) { content }
      end
    end

    describe '#display_status' do
      it 'reads open while Captain attends a pending conversation' do
        conversation = create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant)

        expect(conversation.display_status).to eq('open')
        expect(conversation.status).to eq('pending')
      end

      it 'is the real status otherwise' do
        pending = create_conversation(account: account, inbox: plain_inbox, status: :pending)
        resolved = create_conversation(account: account, inbox: inbox, status: :resolved, ai_assignee: assistant)

        expect(pending.display_status).to eq('pending')
        expect(resolved.display_status).to eq('resolved')
      end

      it 'selects with displayed_as: open adds what Captain attends, pending leaves it out' do
        attended = create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant)
        plain_pending = create_conversation(account: account, inbox: plain_inbox, status: :pending)
        plain_open = create_conversation(account: account, inbox: plain_inbox, status: :open)
        resolved = create_conversation(account: account, inbox: plain_inbox, status: :resolved)

        expect(account.conversations.displayed_as('open')).to contain_exactly(attended, plain_open)
        expect(account.conversations.displayed_as('pending')).to contain_exactly(plain_pending)
        expect(account.conversations.displayed_as('resolved')).to contain_exactly(resolved)
      end
    end

    describe 'queue scopes' do
      let!(:ai_conversation) { create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant) }
      let!(:escalated_conversation) do
        create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: assistant).tap(&:bot_handoff!)
      end
      let!(:open_conversation) { create_conversation(account: account, inbox: inbox, status: :open) }
      let!(:mine) { create_conversation(account: account, inbox: inbox, status: :open, assignee: agent) }
      let!(:pending_with_agent) { create_conversation(account: account, inbox: inbox, status: :pending, assignee: agent) }
      let!(:bot_owned) do
        create_conversation(account: account, inbox: inbox, status: :pending, ai_assignee: create(:agent_bot, account: account))
      end
      let!(:plain_pending) { create_conversation(account: account, inbox: plain_inbox, status: :pending) }

      it 'attended_by_ai includes the pending conversations Captain owns, not those a person or a bot owns' do
        expect(account.conversations.attended_by_ai).to contain_exactly(ai_conversation)
        expect(pending_with_agent.reload.ai_assignee).to be_nil
      end

      it 'queue_unassigned leaves out what Captain attends and what a person owns, and keeps AgentBot-owned rows like develop' do
        expect(account.conversations.queue_unassigned).to contain_exactly(escalated_conversation, open_conversation, plain_pending, bot_owned)
        expect(account.conversations.queue_unassigned.pluck(:id))
          .to match_array(account.conversations.without_human_assignee.where.not(id: ai_conversation.id).pluck(:id))
      end

      it 'keeps the upstream unassigned scope untouched' do
        expect(account.conversations.unassigned).to include(escalated_conversation, open_conversation, plain_pending)
        expect(account.conversations.unassigned).not_to include(ai_conversation, bot_owned, mine)
      end
    end
  end
end
