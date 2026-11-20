require 'rails_helper'

RSpec.describe Captain::Decisions::Afterwards do
  let(:conversation) { create(:conversation) }
  let(:assistant) { create(:captain_assistant, account: conversation.account) }
  let(:decision) { create(:captain_decision, conversation: conversation, account: conversation.account, assistant: assistant) }

  it 'uses an exact retained reopening before ending at its incoming turn' do
    decision
    travel 1.minute do
      incoming = create(:message, account: conversation.account, conversation: conversation, message_type: :incoming)
      Captain::Decisions::ControlRecording.new(conversation, assistant).record('reopen', incoming.id, trigger: 'customer_message', anchor: incoming)
    end
    expect(described_class.build(decision)[:facts].pluck(:type)).to eq(%w[reopened new_incoming])
  end

  it 'uses the exact human-control decision once, without duplicating its activity' do
    decision
    travel 1.minute do
      attributes = { activity: { type: 'conversation_status_changed', status: 'open', previous_status: 'resolved' } }
      activity = create(:message, account: conversation.account, conversation: conversation, message_type: :activity, content_attributes: attributes)
      Captain::Decisions::ControlRecording.new(conversation, assistant).record('human_control', activity.id, trigger: 'human_action',
                                                                                                             anchor: activity)
    end
    expect(described_class.build(decision)[:facts].pluck(:type)).to eq(['human_control'])
  end

  it 'stops before later control changes after a new customer turn' do
    decision
    travel 1.minute do
      create(:message, account: conversation.account, conversation: conversation, message_type: :incoming)
    end
    travel 2.minutes do
      Captain::Decisions::ControlRecording.new(conversation, assistant).record('disengage', 'later', trigger: 'assignment')
    end
    expect(described_class.build(decision)[:facts].pluck(:type)).to eq(['new_incoming'])
  end

  it 'does not lose the next incoming after deduplicating a control activity' do
    decision
    travel 1.minute do
      attributes = { activity: { type: 'conversation_status_changed', status: 'open', previous_status: 'resolved' } }
      activity = create(:message, account: conversation.account, conversation: conversation, message_type: :activity, content_attributes: attributes)
      Captain::Decisions::ControlRecording.new(conversation, assistant).record('human_control', activity.id,
                                                                               trigger: 'human_action', anchor: activity)
    end
    travel 2.minutes do
      create(:message, account: conversation.account, conversation: conversation, message_type: :incoming)
    end
    expect(described_class.build(decision)[:facts].pluck(:type)).to eq(%w[human_control new_incoming])
  end
end
