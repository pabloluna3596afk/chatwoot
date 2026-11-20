require 'rails_helper'

RSpec.describe Captain::Followup::Closer do
  let(:account) { create(:account, locale: 'en') }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, additional_attributes: { 'keep' => 'value' }).reload }
  let(:now) { Time.current.change(usec: 0) }

  before do
    account.enable_features!('captain_integration_v2')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
  end

  after { Current.reset }

  it 'resolves with the private note and leaves the re-engagement mark without losing attributes' do
    expect(described_class.new(conversation, assistant, now: now).perform).to eq(:closed)
    expect(conversation.reload).to be_resolved
    expect(conversation.messages.where(private: true).last.content).to eq(I18n.t('captain.followup.closed_note', assistant: assistant.name))
    expect(conversation.additional_attributes).to include(
      'keep' => 'value',
      Captain::Followup::Reengager::STATE_KEY => { 'closed_at' => now.utc.iso8601, 'assistant_id' => assistant.id }
    )
  end

  it 'uses the given full note key' do
    described_class.new(conversation, assistant, note_key: 'captain.notes.closed_unanswered').perform
    expect(conversation.messages.where(private: true).last.content).to eq(
      "#{assistant.name} closed the conversation: the customer did not reply."
    )
  end

  [true, false].product([true, false]).each do |enabled, inside_window|
    it "sends the goodbye only when enabled=#{enabled} and inside_window=#{inside_window}" do
      assistant.update!(config: assistant.config.merge('send_inactivity_resolution_message' => enabled, 'resolution_message' => 'Goodbye'))
      allow(conversation).to receive(:can_reply?).and_return(inside_window)
      described_class.new(conversation, assistant).perform
      expect(conversation.messages.where(private: false, message_type: :outgoing).pluck(:content)).to eq(
        enabled && inside_window ? ['Goodbye'] : []
      )
    end
  end

  it 'suppresses the goodbye for a silent close even when enabled' do
    assistant.update!(send_inactivity_resolution_message: true)
    described_class.new(conversation, assistant, send_resolution_message: false).perform
    expect(conversation.messages.where(private: false, message_type: :outgoing)).to be_empty
  end

  it 'does not close or send twice when repeated' do
    closer = described_class.new(conversation, assistant)
    expect(closer.perform).to eq(:closed)
    expect { closer.perform }.not_to(change { conversation.messages.count })
  end

  it 'leaves a human-assigned conversation unchanged' do
    conversation.update!(assignee: create(:user, account: account))
    expect { described_class.new(conversation, assistant).perform }.not_to(change { conversation.messages.count })
    expect(conversation.reload).to be_pending
  end

  it 'does not close another assistant conversation' do
    other = create(:captain_assistant, account: account)
    conversation.update!(ai_assignee: other)
    expect { described_class.new(conversation, assistant).perform }.not_to(change { conversation.messages.count })
    expect(conversation.reload).to be_pending
  end
end
