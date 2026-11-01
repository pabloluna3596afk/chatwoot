require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::SummarizeConversationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  it 'returns authorized messages with source references and marks private notes' do
    public_message = create(:message, conversation: conversation, content: 'Public response', sender: conversation.contact)
    private_message = create(:message, conversation: conversation, content: 'Private internal note', private: true, sender: user)

    result = service.execute(conversation_id: conversation.display_id)

    expect(result).to include('UNTRUSTED_DATA_BEGIN', 'UNTRUSTED_DATA_END', "message_id=#{public_message.id}",
                              public_message.created_at.iso8601, 'Public response', "message_id=#{private_message.id}",
                              '[PRIVATE NOTE]', 'Private internal note')
  end

  it 'rejects a conversation outside the user scope and another account' do
    agent = create(:user, role: :agent, account: account)
    other_conversation = create(:conversation)
    other_account_service = described_class.new(assistant, user: agent)
    inaccessible = create(:conversation, account: account)

    expect(other_account_service.execute(conversation_id: other_conversation.display_id)).to eq('Conversation not found')
    expect(other_account_service.execute(conversation_id: inaccessible.display_id)).to eq('Conversation not found')
  end

  it 'honors a custom role and inbox membership for transcript reads' do
    agent = create(:user, role: :agent, account: account)
    create(:inbox_member, user: agent, inbox: conversation.inbox)
    custom_role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
    AccountUser.find_by!(account: account, user: agent).update!(custom_role: custom_role)
    conversation.update!(assignee: agent)
    service = described_class.new(assistant, user: agent)

    expect(service.execute(conversation_id: conversation.display_id)).to include("Conversation ##{conversation.display_id}")
  end

  it 'validates limit bounds and reports omitted older messages' do
    3.times { |index| create(:message, conversation: conversation, content: "Message #{index}") }

    expect(service.execute(conversation_id: conversation.display_id, limit: 0)).to include(error: 'limit must be an integer from 1 to 100')
    expect(service.execute(conversation_id: conversation.display_id, limit: 1)).to include('+2 earlier messages not included')
  end
end
