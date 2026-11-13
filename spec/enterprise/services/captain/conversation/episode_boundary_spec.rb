require 'rails_helper'

RSpec.describe Captain::Conversation::EpisodeBoundary do
  let(:conversation) { create(:conversation) }

  it 'returns nil when the conversation was never resolved' do
    expect(described_class.last_resolved_at(conversation)).to be_nil
  end

  it 'returns the time of the latest resolution' do
    create(:message, conversation: conversation, message_type: :activity, created_at: 2.days.ago,
                     content_attributes: { activity: { type: 'conversation_status_changed', status: 'resolved' } })
    latest = create(:message, conversation: conversation, message_type: :activity, created_at: 1.day.ago,
                              content_attributes: { activity: { type: 'conversation_status_changed', status: 'resolved' } })

    expect(described_class.last_resolved_at(conversation)).to eq(latest.reload.created_at)
  end

  it 'ignores other activity messages' do
    create(:message, conversation: conversation, message_type: :activity,
                     content_attributes: { activity: { type: 'conversation_status_changed', status: 'open' } })
    create(:message, conversation: conversation, message_type: :activity,
                     content_attributes: { activity: { type: 'assignee_changed', status: 'resolved' } })

    expect(described_class.last_resolved_at(conversation)).to be_nil
  end
end
