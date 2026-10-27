require 'rails_helper'

RSpec.describe Captain::Copilot::Actions do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'administrator') }
  let(:conversation) { create(:conversation, account: account) }

  it 'adds an account label to a conversation after validation' do
    label = create(:label, account: account, title: 'follow-up')
    action = Captain::Copilot::Actions::AddLabel.new(
      account: account, user: user, target_type: 'Conversation', target_id: conversation.display_id,
      payload: { label_id: label.id }
    )

    action.validate
    result = action.execute

    expect(result[:code]).to eq('label_added')
    expect(conversation.reload.label_list).to include('follow-up')
  end

  it 'keeps private notes private when it reuses the agent message builder' do
    action = Captain::Copilot::Actions::PrivateNote.new(
      account: account, user: user, target_type: 'Conversation', target_id: conversation.display_id,
      payload: { content: 'Internal follow-up' }
    )

    action.validate
    result = action.execute

    message = conversation.messages.find(result[:message_id])
    expect(message).to be_private
    expect(message.content).to eq('Internal follow-up')
  end

  it 'rejects labels from another account' do
    label = create(:label, account: create(:account), title: 'foreign')
    action = Captain::Copilot::Actions::AddLabel.new(
      account: account, user: user, target_type: 'Conversation', target_id: conversation.display_id,
      payload: { label_id: label.id }
    )

    expect { action.validate }.to raise_error(ArgumentError, 'Label does not exist in this account')
  end
end
