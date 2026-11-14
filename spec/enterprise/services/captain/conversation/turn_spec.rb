require 'rails_helper'

RSpec.describe Captain::Conversation::Turn do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  it "is the customer's turn when Captain spoke last" do
    create(:message, account: account, conversation: conversation, sender: assistant, message_type: :outgoing)
    expect(described_class.awaiting_customer?(conversation, assistant)).to be(true)
  end

  it 'ignores follow-up nudges, private notes and activities' do
    message = create(:message, account: account, conversation: conversation, sender: assistant, message_type: :outgoing)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, content_attributes: { captain_followup: 'nudge' })
    create(:message, account: account, conversation: conversation, message_type: :outgoing, private: true)
    create(:message, account: account, conversation: conversation, message_type: :activity)
    expect(described_class.last_message(conversation)).to eq(message)
  end

  it "is Captain's turn when the customer spoke last" do
    create(:message, account: account, conversation: conversation, sender: assistant, message_type: :outgoing)
    create(:message, account: account, conversation: conversation, sender: conversation.contact, message_type: :incoming)
    expect(described_class.awaiting_customer?(conversation, assistant)).to be(false)
  end

  it "is not the customer's turn when a human agent spoke last" do
    create(:message, account: account, conversation: conversation, sender: create(:user, account: account), message_type: :outgoing)
    expect(described_class.awaiting_customer?(conversation, assistant)).to be(false)
  end

  it 'does not attribute another assistant message to this assistant' do
    create(:message, account: account, conversation: conversation, sender: create(:captain_assistant, account: account), message_type: :outgoing)
    expect(described_class.awaiting_customer?(conversation, assistant)).to be(false)
  end

  it 'scans only the last 10 public messages' do
    create(:message, account: account, conversation: conversation, sender: assistant, message_type: :outgoing, created_at: 1.hour.ago)
    create_list(:message, 10, account: account, conversation: conversation, message_type: :outgoing,
                              content_attributes: { captain_followup: 'nudge' })
    expect(described_class.last_message(conversation)).to be_nil
  end

  it 'breaks timestamp ties by id' do
    time = Time.current
    create(:message, account: account, conversation: conversation, sender: assistant, message_type: :outgoing, created_at: time)
    message = create(:message, account: account, conversation: conversation, sender: conversation.contact, message_type: :incoming, created_at: time)
    expect(described_class.last_message(conversation)).to eq(message)
  end
end
