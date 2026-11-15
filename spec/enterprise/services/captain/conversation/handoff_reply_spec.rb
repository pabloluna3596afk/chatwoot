require 'rails_helper'

RSpec.describe Captain::Conversation::HandoffReply do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, out_of_office_message: 'We are closed.') }
  let(:assistant) { create(:captain_assistant, account: account, config: { handoff_message: 'The team will help.' }) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:reply) { described_class.new(conversation, assistant, fallback: 'Default handoff') }

  before { allow(inbox).to receive(:out_of_office?).and_return(true) }

  it 'sends only the out-of-office message outside business hours' do
    expect(reply.perform).to eq(:out_of_office)
    expect(conversation.messages.where(private: false).pluck(:content)).to eq(['We are closed.'])
    expect(reply.message).to be_persisted
  end

  it 'sends the handoff message inside business hours' do
    allow(inbox).to receive(:out_of_office?).and_return(false)

    expect(reply.perform).to eq(:handoff_message)
    expect(conversation.messages.where(private: false).pluck(:content)).to eq(['The team will help.'])
  end

  it 'sends the handoff message when the inbox has no out-of-office message' do
    inbox.update!(out_of_office_message: '')

    expect(reply.perform).to eq(:handoff_message)
    expect(conversation.messages.where(private: false).pluck(:content)).to eq(['The team will help.'])
  end

  it 'sends the handoff message for campaign conversations' do
    conversation.update!(campaign: create(:campaign, account: account, inbox: inbox))
    expect(MessageTemplates::Template::OutOfOffice).not_to receive(:perform_if_applicable)

    expect(reply.perform).to eq(:handoff_message)
    expect(conversation.messages.where(private: false).pluck(:content)).to eq(['The team will help.'])
  end

  it 'falls back to the handoff message when the out-of-office message could not be saved' do
    allow(conversation.messages).to receive(:create!).and_call_original
    allow(conversation.messages).to receive(:create!).with(hash_including(message_type: :template)).and_raise(ActiveRecord::RecordInvalid)

    expect(reply.perform).to eq(:handoff_message)
    expect(conversation.messages.where(private: false).pluck(:content)).to eq(['The team will help.'])
  end

  it 'does not trust a true return value without a persisted message' do
    allow(MessageTemplates::Template::OutOfOffice).to receive(:perform_if_applicable).and_return(true)

    expect(reply.perform).to eq(:handoff_message)
    expect(conversation.messages.where(private: false).count).to eq(1)
  end

  it 'sends nothing when there is no handoff message and no fallback' do
    allow(inbox).to receive(:out_of_office?).and_return(false)
    assistant.update!(config: {})

    expect(described_class.new(conversation, assistant).perform).to be_nil
    expect(conversation.messages.where(private: false)).to be_empty
  end

  it 'uses the fallback when there is no configured message' do
    allow(inbox).to receive(:out_of_office?).and_return(false)
    assistant.update!(config: {})

    expect(reply.perform).to eq(:handoff_message)
    expect(reply.message.content).to eq('Default handoff')
  end

  it 'recognizes the saved out-of-office message after Liquid variables are resolved' do
    inbox.update!(out_of_office_message: 'Hello {{contact.name}}, we are closed.')

    expect(reply.perform).to eq(:out_of_office)
    expect(conversation.messages.where(private: false).pluck(:content)).to eq(["Hello #{conversation.contact.name}, we are closed."])
  end

  it 'does not mistake an older template for a successful send' do
    create(:message, conversation: conversation, message_type: :template, content: 'We are closed.', created_at: 1.hour.ago)
    allow(MessageTemplates::Template::OutOfOffice).to receive(:perform_if_applicable).and_return(true)

    expect(reply.perform).to eq(:handoff_message)
    expect(reply.message.content).to eq('The team will help.')
  end
end
