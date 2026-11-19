require 'rails_helper'
require 'pdf/reader'

RSpec.describe 'dev:attachments_demo' do # rubocop:disable RSpec/DescribeClass -- exercises the named Rake entry point
  let(:task) { Rake::Task['dev:attachments_demo'] }
  let(:account) { create(:account) }

  it 'creates every channel and scenario without delivery jobs and is idempotent', :aggregate_failures do
    create(:user, account: account, role: :administrator)
    clear_enqueued_jobs
    with_modified_env ACCOUNT_ID: account.id.to_s, RESET: nil do
      expect { task.execute }.to output(%r{API: /app/accounts/.*reply:text}m).to_stdout
      counts = [Inbox.count, Contact.count, Conversation.count, Message.count, Attachment.count, ActiveStorage::Blob.count]
      ids = account.conversations.order(:id).pluck(:id)
      expect { task.execute }.to output(/message/).to_stdout
      expect([Inbox.count, Contact.count, Conversation.count, Message.count, Attachment.count, ActiveStorage::Blob.count]).to eq(counts)
      expect(account.conversations.order(:id).pluck(:id)).to eq(ids)
    end
    expect(enqueued_jobs).to be_empty
    expect(account.inboxes.pluck(:channel_type)).to match_array(Seeders::AttachmentsDemo::CHANNELS.values)
    expect(account.conversations.count).to eq(8)
    grid_counts = [2, 3, 4, 6, 7]
    expected_files = %w[normal.png photo.jpg animated.gif image.webp tall.png wide.png tiny.png receipt.png
                        quotation_marzo_version_final.pdf large.pdf contract.docx prices.xlsx documents.zip readme.txt
                        audio.mp3 voice.ogg video.mp4 sticker.webp]
    account.conversations.each do |conversation|
      expect(conversation.attachments.pluck(:file_type).uniq).to include('image', 'file', 'audio', 'video', 'contact', 'location')
      expect(conversation.attachments.joins(file_attachment: :blob).pluck('active_storage_blobs.filename').uniq).to match_array(expected_files)
      grid_counts.each do |count|
        expect(conversation.messages.find_by!('source_id LIKE ?', "%:grid:#{count}").attachments.count).to eq(count)
      end
      expect(conversation.messages.where(private: true).sole.attachments.count).to eq(2)
      tall = conversation.attachments.joins(file_attachment: :blob).find_by!(active_storage_blobs: { filename: 'tall.png' })
      expect(tall.file.metadata.slice('width', 'height')).to eq('width' => 1000, 'height' => 4000)
      expect(conversation.messages.failed.sole.external_error).to include('simulated')
      replies = conversation.messages.where("source_id LIKE '%:reply:%'")
      expect(replies.count).to eq(3)
      replies.each { |reply| expect(conversation.messages.exists?(id: reply.in_reply_to)).to be(true) }
      large = conversation.attachments.joins(file_attachment: :blob).find_by!(active_storage_blobs: { filename: 'large.pdf' })
      expect(large.file.byte_size).to be >= 5.megabytes
      expect(PDF::Reader.new(StringIO.new(large.file.download)).page_count).to eq(3)
    end
    email = account.conversations.joins(:inbox).find_by!(inboxes: { channel_type: 'Channel::Email' }).messages.incoming_email.sole
    expect(email.attachments.count).to eq(3)
    expect(email.content_attributes.dig('email', 'html_content', 'full')).to include('/rails/active_storage/blobs/')
    mime = Mail.read_from_string(email.additional_attributes.fetch('attachments_demo_mime'))
    expect(mime.html_part.body.decoded).to include('cid:receipt@attachments.demo')
    expect(mime.attachments.count).to eq(4)
  end

  it 'uses a genuinely missing local URL for the expired-media scenario' do
    request = ActionDispatch::Integration::Session.new(Rails.application)
    request.get Seeders::AttachmentsDemo::Scenarios::EXPIRED_PATH
    expect(request.response.status).to eq(404)
  end

  it 'resets only its messages, preserving manually added messages and unrelated account data' do
    other = create(:conversation)
    with_modified_env ACCOUNT_ID: account.id.to_s, RESET: nil do
      expect { task.execute }.to output(/message/).to_stdout
      conversation = account.conversations.first
      manual = create(:message, conversation: conversation, account: account, inbox: conversation.inbox, content: 'Keep me')
      original_ids = conversation.messages.where.not(id: manual.id).pluck(:id)
      with_modified_env RESET: '1' do
        expect { task.execute }.to output(/message/).to_stdout
      end
      expect(manual.reload.content).to eq('Keep me')
      expect(other.reload).to be_persisted
      expect(Message.where(id: original_ids)).not_to exist
      expect(account.conversations.count).to eq(8)
      expect(conversation.reload.messages.count).to eq(original_ids.size + 1)
    end
  end

  it 'aborts in production before looking up an account or writing data' do
    allow(Rails.env).to receive(:production?).and_return(true)
    expect(Account).not_to receive(:find)
    expect { task.execute }.to raise_error(SystemExit, /disabled in production/).and output(/disabled in production/).to_stderr
  end
end
