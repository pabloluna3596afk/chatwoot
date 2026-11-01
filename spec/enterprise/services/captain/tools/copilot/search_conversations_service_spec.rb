require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::SearchConversationsService do
  let(:account) { create(:account) }
  let(:user) { create(:user, role: 'administrator', account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  describe '#name' do
    it 'returns the correct service name' do
      expect(service.name).to eq('search_conversation')
    end
  end

  describe '#description' do
    it 'returns the service description' do
      expect(service.description).to include('order_by=last_activity_at', 'repeat once without filters')
    end
  end

  describe '#parameters_schema' do
    it 'defines the expected parameters' do
      expect(service.parameters_schema.fetch('properties').keys).to contain_exactly(
        'status', 'contact_id', 'priority', 'labels', 'created_after', 'created_before', 'last_activity_after',
        'last_activity_before', 'inbox_id', 'assignee_id', 'team_id', 'order_by', 'direction', 'limit'
      )
      expect(service.parameters_schema.fetch('additionalProperties')).to be false
    end
  end

  describe '#active?' do
    context 'when user has conversation_manage permission' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }
      let(:user) { create(:user, account: account) }

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        account_user.update(role: :agent, custom_role: custom_role)
      end

      it 'returns true' do
        expect(service.active?).to be true
      end
    end

    context 'when user has conversation_unassigned_manage permission' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_unassigned_manage']) }
      let(:user) { create(:user, account: account) }

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        account_user.update(role: :agent, custom_role: custom_role)
      end

      it 'returns true' do
        expect(service.active?).to be true
      end
    end

    context 'when user has conversation_participating_manage permission' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }
      let(:user) { create(:user, account: account) }

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        account_user.update(role: :agent, custom_role: custom_role)
      end

      it 'returns true' do
        expect(service.active?).to be true
      end
    end

    context 'when user has no relevant conversation permissions' do
      let(:custom_role) { create(:custom_role, account: account, permissions: []) }
      let(:user) { create(:user, account: account) }

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        account_user.update(role: :agent, custom_role: custom_role)
      end

      it 'returns false' do
        expect(service.active?).to be false
      end
    end
  end

  describe '#execute' do
    let(:contact) { create(:contact, account: account) }
    let!(:open_conversation) { create(:conversation, account: account, contact: contact, status: 'open', priority: 'high') }
    let!(:resolved_conversation) { create(:conversation, account: account, status: 'resolved', priority: 'low') }

    it 'returns all conversations when no filters are applied' do
      result = service.execute
      expect(result).to include('Total number of conversations: 2')
      expect(result).to include(open_conversation.to_llm_text(include_contact_details: true))
      expect(result).to include(resolved_conversation.to_llm_text(include_contact_details: true))
    end

    it 'orders recent conversations deterministically and defaults to ten results' do
      open_conversation.update!(last_activity_at: 2.days.ago)
      resolved_conversation.update!(last_activity_at: 1.day.ago)

      result = service.execute(order_by: 'last_activity_at')

      expect(result.index("Conversation ##{resolved_conversation.display_id}")).to be < result.index("Conversation ##{open_conversation.display_id}")
      expect(result).to include('status: resolved', 'last_activity_at:')
    end

    it 'defaults to ten results without ordering and enforces a twenty-five result maximum' do
      create_list(:conversation, 10, account: account, contact: contact)

      expect(service.execute).to include('showing first 10')
      expect(service.execute(order_by: 'created_at', limit: 25)).to include('Total number of conversations: 12')
    end

    it 'keeps the full search response within its shared character budget' do
      maximum = Captain::Copilot::Limits::SEARCH_RESPONSE_CHARACTERS
      prefix_length = "Total number of conversations: 10\n".length
      record_characters = maximum - prefix_length - (9 * 5)
      per_record, remainder = record_characters.divmod(10)
      records = Array.new(10) { 'x' * per_record }
      records[0] += 'x' * remainder
      conversations = double
      allow(conversations).to receive(:count).and_return(10)
      allow(conversations).to receive(:limit).with(10).and_return(records)
      allow(service).to receive(:conversation_summary) { |record| record }

      expect(service.send(:format_conversations, conversations, 10).length).to eq(maximum)

      records[0] += 'x'
      result = service.send(:format_conversations, conversations, 10)
      expect(result.length).to be <= Captain::Copilot::Limits::SEARCH_RESPONSE_CHARACTERS
      expect(result).to include('[response truncated]')
    end

    it 'passes the shared transcript limits for each search result' do
      expect(open_conversation).to receive(:to_llm_text).with(
        include_contact_details: true,
        include_private_messages: true,
        message_limit: Captain::Copilot::Limits::SEARCH_MESSAGES,
        token_limit: Captain::Copilot::Limits::SEARCH_MESSAGE_CHARACTERS
      ).and_return('bounded transcript')

      expect(service.send(:conversation_summary, open_conversation)).to include('bounded transcript')
    end

    it 'keeps a search transcript exactly at its character budget' do
      content = 'x' * (Captain::Copilot::Limits::SEARCH_MESSAGE_CHARACTERS - 7)
      create(:message, conversation: open_conversation, content: content)

      result = service.send(:conversation_summary, open_conversation)

      expect(result).to include(content)
      expect(result).not_to include('earlier messages not included')
    end

    it 'truncates a search transcript one character above its character budget' do
      create(:message, conversation: open_conversation,
                       content: 'x' * (Captain::Copilot::Limits::SEARCH_MESSAGE_CHARACTERS - 6))

      result = service.send(:conversation_summary, open_conversation)

      expect(result).not_to include('x' * (Captain::Copilot::Limits::SEARCH_MESSAGE_CHARACTERS - 6))
      expect(result).to include('earlier messages not included')
    end

    it 'rejects unsupported order values, directions, and limits' do
      expect(service.execute(order_by: 'random_column')).to include(error: 'order_by must be last_activity_at or created_at')
      expect(service.execute(order_by: 'created_at', direction: 'sideways')).to include(error: 'direction must be asc or desc')
      expect(service.execute(order_by: 'created_at', limit: 26)).to include(error: 'limit must be an integer from 1 to 25')
    end

    it 'filters conversations by status' do
      result = service.execute(status: 'open')
      expect(result).to include('Total number of conversations: 1')
      expect(result).to include(open_conversation.to_llm_text(include_contact_details: true))
      expect(result).not_to include(resolved_conversation.to_llm_text(include_contact_details: true))
    end

    it 'filters conversations by contact_id' do
      result = service.execute(contact_id: contact.id)
      expect(result).to include('Total number of conversations: 1')
      expect(result).to include(open_conversation.to_llm_text(include_contact_details: true))
      expect(result).not_to include(resolved_conversation.to_llm_text(include_contact_details: true))
    end

    it 'filters conversations by priority' do
      result = service.execute(priority: 'high')
      expect(result).to include('Total number of conversations: 1')
      expect(result).to include(open_conversation.to_llm_text(include_contact_details: true))
      expect(result).not_to include(resolved_conversation.to_llm_text(include_contact_details: true))
    end

    it 'returns appropriate message when no conversations are found' do
      result = service.execute(status: 'snoozed')
      expect(result).to eq('No conversations found')
    end

    it 'rejects an invalid status instead of dropping the filter' do
      expect(service.execute(status: 'all')).to include(error: 'status must be open, resolved, pending, or snoozed')
    end

    it 'rejects an invalid priority instead of dropping the filter' do
      expect(service.execute(priority: 'all')).to include(error: 'priority must be low, medium, high, or urgent')
    end

    it 'rejects invalid filters even when another filter is valid' do
      expect(service.execute(status: 'all', contact_id: contact.id)).to include(error: 'status must be open, resolved, pending, or snoozed')
    end

    it 'filters by date, inbox, agent, and team within the authorized scope' do
      open_conversation.update!(assignee: user)
      result = service.execute(created_after: 1.day.ago.iso8601, inbox_id: open_conversation.inbox_id,
                               assignee_id: 'me', team_id: open_conversation.team_id)

      expect(result).to include("Conversation ##{open_conversation.display_id}")
      expect(result).not_to include("Conversation ##{resolved_conversation.display_id}")
    end

    it 'returns no records for an inbox outside the accessible scope without revealing it' do
      other_inbox = create(:inbox, account: create(:account))

      expect(service.execute(inbox_id: other_inbox.id)).to eq('No conversations found')
    end

    it 'rejects malformed dates and invalid date ranges' do
      expect(service.execute(created_after: 'last year')).to include(error: /date filters/)
      result = service.execute(created_after: '2026-05-02', created_before: '2026-05-01')

      expect(result).to include(error: 'date after must be earlier than date before')
      expect(service.execute(created_after: '2024-01-01', created_before: '2026-01-02')).to include(error: /cannot exceed 366 days/)
    end

    context 'when the user has team access without inbox access' do
      let(:user) { create(:user, account: account, role: :agent) }
      let(:team) { create(:team, account: account) }
      let!(:team_conversation) { create(:conversation, :with_team, account: account, team: team) }

      before { create(:team_member, team: team, user: user) }

      it 'returns and counts the team conversation' do
        result = service.execute

        expect(result).to include('Total number of conversations: 1')
        expect(result).to include("Conversation ID: ##{team_conversation.display_id}")
      end
    end

    context 'when the user only has conversation_unassigned_manage permission' do
      let(:user) { create(:user, account: account, role: :agent) }
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_unassigned_manage']) }
      let(:agent_bot) { create(:agent_bot, account: account) }
      let!(:agent_bot_conversation) do
        create(:conversation, account: account, inbox: open_conversation.inbox, ai_assignee: agent_bot)
      end

      before do
        create(:inbox_member, user: user, inbox: open_conversation.inbox)
        AccountUser.find_by!(user: user, account: account).update!(role: :agent, custom_role: custom_role)
        create(:message, conversation: agent_bot_conversation, private: true, content: 'Agent bot private note')
      end

      it 'does not return or count a conversation assigned to an agent bot' do
        result = service.execute

        expect(result).to include('Total number of conversations: 1')
        expect(result).to include("Conversation ID: ##{open_conversation.display_id}")
        expect(result).not_to include("Conversation ID: ##{agent_bot_conversation.display_id}")
        expect(result).not_to include('Agent bot private note')
      end
    end

    context 'when an administrator has a limited custom role' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }

      before do
        AccountUser.find_by!(user: user, account: account).update!(custom_role: custom_role)
        create(:message, conversation: open_conversation, private: true, content: 'Restricted private note')
      end

      it 'does not return or count unrelated conversations' do
        result = service.execute

        expect(result).to eq('No conversations found')
        expect(result).not_to include('Restricted private note')
      end

      it 'returns and counts an assigned conversation outside their inboxes' do
        assigned_conversation = create(:conversation, account: account, assignee: user)

        result = service.execute

        expect(result).to include('Total number of conversations: 1')
        expect(result).to include("Conversation ID: ##{assigned_conversation.display_id}")
        expect(result).not_to include('Restricted private note')
      end
    end

    context 'when an administrator has a conversation_manage custom role' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }

      before { AccountUser.find_by!(user: user, account: account).update!(custom_role: custom_role) }

      it 'returns conversations outside their inboxes' do
        result = service.execute

        expect(result).to include('Total number of conversations: 2')
        expect(result).to include("Conversation ID: ##{open_conversation.display_id}")
        expect(result).to include("Conversation ID: ##{resolved_conversation.display_id}")
      end
    end
  end
end
