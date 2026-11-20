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

  it 'sends the localized handoff, private reason note and usage event' do
    expect(Captain::ConversationEvents).to receive(:handed_off).with(
      conversation: conversation, assistant: assistant, source: 'usage_limit', reason_category: :usage_limit, at: kind_of(Time)
    ).and_call_original

    service.perform

    expect(conversation.reload).to be_open
    expect(conversation.messages.where(private: false).pluck(:content)).to eq([I18n.t('conversations.captain.handoff', locale: 'es')])
    expect(conversation.messages.where(private: true).last).to have_attributes(
      sender: assistant, content: I18n.t('captain.notes.unavailable.quota_exhausted', assistant: assistant.name, locale: 'es')
    )
    expect(conversation.captain_decisions.find_by!(trigger: 'usage_limit')).to have_attributes(
      kind: 'handoff', anchor_message: conversation.messages.where(private: true).last, reason_locale: 'es'
    )
  end

  it 'does not duplicate the usage decision on a repeated handoff' do
    service.perform
    expect { service.perform }.not_to(change { conversation.captain_decisions.where(trigger: 'usage_limit').count })
  end

  it 'keeps the effective handoff when its decision write fails' do
    allow(Captain::Decision).to receive(:create_or_find_by!).and_raise(ActiveRecord::StatementInvalid)
    service.perform
    expect(conversation.reload).to be_open
    expect(conversation.messages.where(private: true).count).to eq(1)
  end

  it 'uses routing on usage-limit handoff without changing the customer reply' do
    assistant.update!(config: assistant.config.merge('handoff_priority' => 'always'))
    expect(Captain::HandoffRouter).to receive(:new).with(conversation: conversation, assistant: assistant).and_call_original
    service.perform
    expect(conversation.reload).to be_high
    expect(conversation.messages.where(private: true).sole.content).to end_with(I18n.t('captain.notes.handoff_routing.priority_high', locale: 'es'))
  end

  it 'sends only the out-of-office message outside hours and leaves one handoff note' do
    inbox.update!(working_hours_enabled: true, out_of_office_message: 'Cerrado')
    inbox.working_hours.each { |hours| hours.update!(closed_all_day: true, open_all_day: false) }

    service.perform

    expect(conversation.messages.where(private: false).pluck(:content)).to eq(['Cerrado'])
    expect(conversation.messages.where(private: true).sole.content_attributes['captain_handoff']).to eq(
      'reason_category' => 'usage_limit', 'source' => 'usage_limit'
    )
  end

  it 'leaves a minimal handoff note when there is no paused reason' do
    put_account_on_plan(account)

    service.perform

    expect(conversation.messages.where(private: true).sole).to have_attributes(
      content: I18n.t('captain.notes.handoff_usage_limit', assistant: assistant.name, locale: 'es'),
      content_attributes: { 'captain_handoff' => { 'reason_category' => 'usage_limit', 'source' => 'usage_limit' } }
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
    expect(conversation.captain_decisions.find_by!(reason_code: 'captain_unavailable')).to have_attributes(
      kind: 'reply', outcome: 'skipped', anchor_message: conversation.messages.where(private: true).sole
    )
  end
end
