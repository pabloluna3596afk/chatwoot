require 'rails_helper'

RSpec.describe Attachment do
  it 'queues a voice note only once when saving it also autosaves its conversation' do
    conversation = create(:conversation, waiting_since: nil)
    message = conversation.messages.build(account: conversation.account, inbox: conversation.inbox,
                                          sender: conversation.contact, message_type: :incoming, content: nil)
    message.attachments.new(
      account_id: conversation.account_id, file_type: :audio,
      file: { io: Rails.root.join('spec/assets/sample.ogg').open, filename: 'voice.ogg', content_type: 'audio/ogg' }
    )

    expect { message.save! }.to have_enqueued_job(Messages::AudioTranscriptionJob).once
  end
end
