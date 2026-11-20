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
                                   names: [assistant.name], source: { type: 'captain', name: assistant.name } }
                     })
    )
  end

  %i[resolved open].product([nil, :tool, :inactivity]).each do |status, reason_type|
    it "keeps Captain's literal name for #{status} with reason #{reason_type.inspect}" do
      conversation
      Current.executed_by = assistant
      conversation.captain_activity_reason = reason_type && 'Customer requested closure'
      conversation.captain_activity_reason_type = reason_type

      perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { conversation.update!(status: status) }

      message = conversation.messages.activity.last
      expect(message.content_attributes.dig('activity', 'names')).to eq([assistant.name])
      expect(message.content).to include(assistant.name)
    end
  end

  it 'preserves human activity metadata'  do
    conversation
    Current.user = create(:user, account: conversation.account)
    expect { conversation.resolved! }.to have_enqueued_job(Conversations::ActivityMessageJob).with(
      conversation,
      hash_including(content_attributes: {
                       activity: { type: 'conversation_status_changed', status: 'resolved', previous_status: 'pending', names: [Current.user.name] }
                     })
    )
  end
end
