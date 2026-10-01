require 'rails_helper'

RSpec.describe ConversationFinder do
  describe '#perform_meta_only' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:other_agent) { create(:user, account: account, role: :agent) }
    let(:inbox) { create(:inbox, account: account) }

    before do
      Current.account = account
      create(:inbox_member, user: agent, inbox: inbox)
      account.account_users.find_by(user: agent).update!(
        role: :agent,
        custom_role: create(:custom_role, account: account, permissions: %w[conversation_participating_manage])
      )
    end

    it 'counts participant-filtered conversations once when assigned conversations have multiple participants' do
      assigned_conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)
      participating_conversation = create(:conversation, account: account, inbox: inbox, assignee: other_agent)
      create(:conversation, account: account, inbox: inbox, assignee: other_agent)

      2.times do
        participant = create(:user, account: account, role: :agent)
        create(:inbox_member, user: participant, inbox: inbox)
        create(:conversation_participant, account: account, conversation: assigned_conversation, user: participant)
      end
      create(:conversation_participant, account: account, conversation: participating_conversation, user: agent)

      result = described_class.new(agent, { status: 'open' }).perform_meta_only

      expect(result[:count]).to eq({
                                     mine_count: 1,
                                     assigned_count: 2,
                                     unassigned_count: 0,
                                     all_count: 2,
                                     ai_count: 0
                                   })
    end
  end

  describe 'Captain views' do
    # Captain starts every new conversation of its inboxes as pending whatever status is asked for, so the
    # status the scenario needs is set afterwards.
    def create_conversation(status:, **attributes)
      create(:conversation, status: status, **attributes).tap do |conversation|
        conversation.update_columns(status: Conversation.statuses.fetch(status.to_s)) # rubocop:disable Rails/SkipsModelValidations
      end
    end
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:other_agent) { create(:user, account: account, role: :agent) }
    let(:captain_inbox) { create(:inbox, account: account) }
    let(:plain_inbox) { create(:inbox, account: account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:agent_bot) { create(:agent_bot, account: account) }
    before do
      Current.account = account
      create(:captain_inbox, inbox: captain_inbox, captain_assistant: assistant)
    end

    let!(:ai_conversation) { create_conversation(account: account, inbox: captain_inbox, status: :pending) }
    let!(:ai_with_owner) { create_conversation(account: account, inbox: captain_inbox, status: :pending, assignee: other_agent) }
    let!(:escalated) { create_conversation(account: account, inbox: captain_inbox, status: :pending).tap(&:bot_handoff!) }
    let!(:open_unassigned) { create_conversation(account: account, inbox: plain_inbox, status: :open) }
    let!(:mine) { create_conversation(account: account, inbox: captain_inbox, status: :open, assignee: admin) }
    let!(:others) { create_conversation(account: account, inbox: plain_inbox, status: :open, assignee: other_agent) }
    let!(:bot_owned) { create_conversation(account: account, inbox: captain_inbox, status: :pending, assignee_agent_bot: agent_bot) }
    let!(:resolved_one) { create_conversation(account: account, inbox: captain_inbox, status: :resolved) }

    def ids(result)
      result[:conversations].map(&:id)
    end

    # develop's fast unassigned_count leaves AgentBot-owned rows out while the list keeps them; the tab rows minus those rows must match it.
    let(:unassigned_rows_without_bots) { ->(result) { result[:conversations].count { |c| c.assignee_agent_bot_id.nil? } } }

    it 'lists what Captain is attending in the AI view whatever status is asked for' do
      result = described_class.new(admin, { conversation_type: 'captain', status: 'open' }).perform

      expect(ids(result)).to contain_exactly(ai_conversation.id, ai_with_owner.id)
      expect(result[:count][:ai_count]).to eq(2)
    end

    it 'keeps what Captain attends out of Sin asignar and lists it once it is escalated' do
      result = described_class.new(admin, { assignee_type: 'unassigned', status: 'open' }).perform

      expect(ids(result)).to contain_exactly(escalated.id, open_unassigned.id)
    end

    it 'lists no AI conversation in Sin asignar for the pending status' do
      result = described_class.new(admin, { assignee_type: 'unassigned', status: 'pending' }).perform

      expect(ids(result)).to contain_exactly(bot_owned.id)
    end

    context 'when an AgentBot owns the conversation (Panel AI inboxes stay as on develop)' do
      let!(:plain_bot_owned) { create_conversation(account: account, inbox: plain_inbox, status: :open, assignee_agent_bot: agent_bot) }

      it 'keeps it in the unassigned list, as without_human_assignee does on develop' do
        result = described_class.new(admin, { assignee_type: 'unassigned', status: 'open' }).perform

        expect(ids(result)).to include(plain_bot_owned.id)
        expect(ids(result)).to match_array(account.conversations.open.without_human_assignee.pluck(:id))
      end

      it 'keeps it out of unassigned_count and inside all_count, as the fast count does on develop' do
        counts = described_class.new(admin, { status: 'open' }).perform_meta_only[:count]
        open_rows = account.conversations.open

        expect(counts[:unassigned_count]).to eq(open_rows.where(assignee_id: nil, assignee_agent_bot_id: nil).count)
        expect(counts[:all_count]).to eq(open_rows.count)
      end

      it 'does not lose it from the pending list because of the Captain assistant of its inbox' do
        result = described_class.new(admin, { assignee_type: 'unassigned', status: 'pending' }).perform

        expect(ids(result)).to include(bot_owned.id)
        expect(ids(result)).not_to include(ai_conversation.id)
      end
    end

    %w[open pending].each do |status|
      it "returns counts equal to the rows of every tab for status #{status}" do
        finder = ->(extra) { described_class.new(admin, { status: status }.merge(extra)).perform }
        counts = finder.call({})[:count]

        expect(finder.call(assignee_type: 'me')[:conversations].length).to eq(counts[:mine_count])
        expect(unassigned_rows_without_bots.call(finder.call(assignee_type: 'unassigned'))).to eq(counts[:unassigned_count])
        expect(finder.call(assignee_type: 'all')[:conversations].length).to eq(counts[:all_count])
        expect(finder.call(assignee_type: 'assigned')[:conversations].length).to eq(counts[:assigned_count])
      end
    end

    it 'returns counts equal to the rows of every tab with status all' do
      finder = ->(extra) { described_class.new(admin, { status: 'all' }.merge(extra)).perform }
      counts = finder.call({})[:count]

      expect(finder.call(assignee_type: 'me')[:conversations].length).to eq(counts[:mine_count])
      expect(unassigned_rows_without_bots.call(finder.call(assignee_type: 'unassigned'))).to eq(counts[:unassigned_count])
      expect(finder.call(assignee_type: 'all')[:conversations].length).to eq(counts[:all_count])
    end

    it 'returns an ai_count equal to the rows of the AI view' do
      counts = described_class.new(admin, { status: 'open' }).perform_meta_only[:count]
      rows = described_class.new(admin, { conversation_type: 'captain' }).perform[:conversations]

      expect(counts[:ai_count]).to eq(rows.length)
    end

    it 'does not count AI conversations of inboxes the agent cannot see' do
      create(:inbox_member, user: other_agent, inbox: plain_inbox)
      account.account_users.find_by(user: other_agent).update!(role: :agent)

      counts = described_class.new(other_agent, { status: 'open' }).perform_meta_only[:count]

      expect(counts[:ai_count]).to eq(0)
    end
  end
end
