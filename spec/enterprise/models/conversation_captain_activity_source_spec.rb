require 'rails_helper'

RSpec.describe Conversation do
  let(:conversation) { create(:conversation, status: :pending) }
  let(:assistant) { create(:captain_assistant, account: conversation.account) }

  after { Current.reset }

  it 'marks Captain resolution activities without changing structured status facts' do
    conversation
    Current.executed_by = assistant
    expect { conversation.resolved! }.to have_enqueued_job(Conversations::ActivityMessageJob).with(
      conversation,
      hash_including(content_attributes: {
                       activity: { type: 'conversation_status_changed', status: 'resolved', previous_status: 'pending',
                                   source: { type: 'captain', name: assistant.name } }
                     })
    )
  end

  it 'preserves human activity metadata' do
    conversation
    Current.user = create(:user, account: conversation.account)
    expect { conversation.resolved! }.to have_enqueued_job(Conversations::ActivityMessageJob).with(
      conversation,
      hash_including(content_attributes: {
                       activity: { type: 'conversation_status_changed', status: 'resolved', previous_status: 'pending' }
                     })
    )
  end
end
