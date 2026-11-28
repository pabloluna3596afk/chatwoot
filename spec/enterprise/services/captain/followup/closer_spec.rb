require 'rails_helper'

RSpec.describe Captain::Followup::Closer do
  let(:account) { create(:account, locale: 'en') }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, additional_attributes: { 'keep' => 'value' }).reload }
  let(:now) { Time.current.change(usec: 0) }

  before do
    account.enable_features!('captain_integration', 'captain_integration_v2')
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
    expect(conversation.captain_decisions.where(kind: 'close_unanswered').count).to eq(1)
  end

  it 'records the effective close with its existing note, last turn, wait and historical settings' do
    turn = create(:message, account: account, inbox: inbox, conversation: conversation, sender: assistant,
                            message_type: :outgoing, created_at: now - 4.hours)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: assistant,
                     message_type: :outgoing, created_at: now - 3.hours, content_attributes: { captain_followup: 'nudge' })
    described_class.new(conversation, assistant, now: now).perform
    decision = conversation.captain_decisions.find_by!(kind: 'close_unanswered')
    expect(decision.anchor_message).to eq(conversation.messages.where(private: true).last)
    expect(decision.evidence).to eq('evaluated_through_message_id' => turn.id, 'nudges_sent' => 1, 'wait_seconds' => 10_800)
    expect(decision.settings_snapshot).to eq('inactivity_threshold_minutes' => assistant.inactivity_threshold_minutes)
    expect(decision.reason_text).to include('Silence does not confirm')
    expect(decision.reason_locale).to eq('en')
  end

  it 'still closes if the decision write fails' do
    allow(Captain::Decision).to receive(:create_or_find_by!).and_raise(ActiveRecord::StatementInvalid)
    expect(described_class.new(conversation, assistant).perform).to eq(:closed)
    expect(conversation.reload).to be_resolved
    expect(conversation.captain_decisions).to be_empty
  end

  it 'retains the applied threshold when the eligibility check reloads changed settings' do
    closer = described_class.new(conversation, assistant)
    applied = assistant.inactivity_threshold_minutes
    assistant.update!(config: assistant.config.merge('auto_resolve_after' => applied + 5))
    closer.perform
    expect(conversation.captain_decisions.find_by!(kind: 'close_unanswered').settings_snapshot).to eq('inactivity_threshold_minutes' => applied)
  end

  it 'rolls back the note and decision with the effective close' do
    conversation
    Conversation.transaction do
      described_class.new(conversation, assistant).perform
      raise ActiveRecord::Rollback
    end
    expect(conversation.reload).to be_pending
    expect(conversation.messages.where(private: true)).to be_empty
    expect(conversation.captain_decisions).to be_empty
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
