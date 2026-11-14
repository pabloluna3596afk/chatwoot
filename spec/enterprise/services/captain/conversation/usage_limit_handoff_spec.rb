require 'rails_helper'

RSpec.describe Captain::Conversation::UsageLimitHandoff do
  let(:account) { create(:account, locale: 'es') }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, status: :pending) }
  let(:service) { described_class.new(conversation: conversation) }

  before do
    put_account_on_plan(account, monthly_messages: 1, used: 1)
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
  end

  it 'sends the localized handoff, private reason note, usage event and out of office notice' do
    expect(Captain::ConversationEvents).to receive(:handed_off).with(
      conversation: conversation, assistant: assistant, source: 'usage_limit', reason_category: :usage_limit, at: kind_of(Time)
    ).and_call_original
    expect(MessageTemplates::Template::OutOfOffice).to receive(:perform_if_applicable).with(conversation)

    service.perform

    expect(conversation.reload).to be_open
    expect(conversation.messages.where(private: false).pluck(:content)).to eq([I18n.t('conversations.captain.handoff', locale: 'es')])
    expect(conversation.messages.where(private: true).last).to have_attributes(
      sender: assistant, content: I18n.t('captain.notes.unavailable.quota_exhausted', assistant: assistant.name, locale: 'es')
    )
  end

  it 'uses the configured handoff message' do
    assistant.update!(config: assistant.config.merge('handoff_message' => 'Te atenderá el equipo'))

    service.perform

    expect(conversation.messages.where(private: false).pluck(:content)).to eq(['Te atenderá el equipo'])
  end

  it 'does not send an out of office message for campaigns' do
    conversation.update!(campaign: create(:campaign, inbox: inbox, account: account))
    expect(MessageTemplates::Template::OutOfOffice).not_to receive(:perform_if_applicable)

    service.perform

    expect(conversation.reload).to be_open
  end

  it 'can leave only an unavailable note before Captain takes a conversation' do
    conversation.update!(status: :open)

    service.create_unavailable_note

    expect(conversation.messages.where(private: false)).to be_empty
    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(conversation.reload).to be_open
  end
end
