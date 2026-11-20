require 'rails_helper'

RSpec.describe Captain::Decisions::Recorder do
  let(:conversation) { create(:conversation) }
  let(:assistant) { create(:captain_assistant, account: conversation.account) }
  let(:attributes) do
    { conversation: conversation, assistant: assistant, decision_key: 'resolve:turn:1',
      kind: 'resolve', outcome: 'completed', origin: 'tool', trigger: 'tool', reason_code: 'tool_resolve' }
  end

  it 'records the same execution once and returns its existing ID' do
    first = described_class.record(**attributes)
    expect(first).to be_persisted
    expect { expect(described_class.record(**attributes).id).to eq(first.id) }.not_to change(Captain::Decision, :count)
  end

  it 'keeps the action usable after a rejected decision' do
    Conversation.transaction do
      expect(described_class.record(**attributes, reason_text: 'x' * 501)).to be_nil
      conversation.update!(priority: :high)
    end
    expect(conversation.reload.priority).to eq('high')
  end

  it 'isolates PostgreSQL insert errors with a savepoint and logs no payload' do
    allow(Captain::Decision).to receive(:create_or_find_by!).and_wrap_original do |_method, **_args|
      Captain::Decision.connection.execute('SELECT 1 / 0')
    end
    allow(Rails.logger).to receive(:error)
    Conversation.transaction do
      expect(described_class.record(**attributes)).to be_nil
      conversation.update!(priority: :urgent)
    end
    expect(conversation.reload.priority).to eq('urgent')
    expect(Rails.logger).to have_received(:error).with(/error=ActiveRecord::StatementInvalid/)
  end

  it 'isolates evidence construction failures from the action' do
    Conversation.transaction do
      expect(described_class.record(**attributes) { raise 'sensitive tool output' }).to be_nil
      conversation.update!(priority: :high)
    end
    expect(conversation.reload.priority).to eq('high')
  end

  it 'rolls back a successful record when the action rolls back' do
    expect do
      Conversation.transaction do
        described_class.record(**attributes)
        raise ActiveRecord::Rollback
      end
    end.not_to change(Captain::Decision, :count)
  end
end
