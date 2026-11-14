require 'rails_helper'

RSpec.describe Captain::Followup::Closer do
  let(:account) { create(:account, locale: 'en') }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending, additional_attributes: { 'keep' => 'value' }) }
  let(:now) { Time.current.change(usec: 0) }

  before { account.enable_features!('captain_integration_v2') }

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
end
