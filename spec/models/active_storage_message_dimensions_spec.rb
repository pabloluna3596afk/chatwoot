require 'rails_helper'

RSpec.describe ActiveStorageMessageDimensions do
  let!(:message) { create(:message, :with_attachment) }
  let(:attachment) { message.attachments.first }
  let(:blob) { attachment.file.blob }
  let(:dispatcher) { Rails.configuration.dispatcher }

  # The image analyzer is faked so the specs do not depend on libvips or ImageMagick being installed.
  let(:image_analyzer) do
    Class.new(ActiveStorage::Analyzer) do
      def self.accept?(blob)
        blob.image?
      end

      def metadata
        { width: 256, height: 256 }
      end
    end
  end

  before do
    allow(ActiveStorage).to receive(:analyzers)
      .and_return([image_analyzer, ActiveStorage::Analyzer::VideoAnalyzer, ActiveStorage::Analyzer::AudioAnalyzer])
    allow(dispatcher).to receive(:dispatch)
  end

  it 'dispatches the analyzed dimensions in the message update payload exactly once' do
    expect(attachment.push_event_data).to include(width: nil, height: nil)
    expect(dispatcher).to receive(:dispatch).with(
      Events::Types::MESSAGE_UPDATED, kind_of(Time), hash_including(message: have_attributes(id: message.id))
    ).once do |_event, _time, data|
      expect(data[:message].push_event_data[:attachments]).to include(hash_including(id: attachment.id, width: 256, height: 256))
    end

    ActiveStorage::AnalyzeJob.perform_now(blob)
    ActiveStorage::AnalyzeJob.perform_now(blob.reload)
    blob.update!(metadata: blob.metadata.merge('custom' => { 'label' => 'unchanged dimensions' }))

    expect(blob.reload).to be_analyzed
  end

  it 'does not enqueue another analysis when broadcasting the update' do
    expect { ActiveStorage::AnalyzeJob.perform_now(blob) }.not_to have_enqueued_job(ActiveStorage::AnalyzeJob)
  end

  it 'sends the dimensions through the real ActionCable listener' do
    create(:user, account: message.account, role: :administrator)
    allow(dispatcher).to receive(:dispatch).and_call_original
    allow(ActionCableBroadcastJob).to receive(:perform_later)
    expect(ActionCableBroadcastJob).to receive(:perform_later).with(
      anything, 'message.updated', hash_including(attachments: [hash_including(id: attachment.id, width: 256, height: 256)]), any_args
    ).at_least(:once)

    ActiveStorage::AnalyzeJob.perform_now(blob)
  end

  it 'broadcasts once per message when the same blob is attached twice' do
    message.attachments.create!(account: message.account, file_type: :image, file: blob)
    expect(dispatcher).to receive(:dispatch).with(
      Events::Types::MESSAGE_UPDATED, kind_of(Time), hash_including(message: have_attributes(id: message.id))
    ).once

    ActiveStorage::AnalyzeJob.perform_now(blob)
  end

  it 'updates every message sharing the blob' do
    other_message = create(:message, account: message.account)
    other_message.attachments.create!(account: message.account, file_type: :image, file: blob)
    expect(dispatcher).to receive(:dispatch).with(
      Events::Types::MESSAGE_UPDATED, kind_of(Time), hash_including(message: have_attributes(id: message.id))
    ).once
    expect(dispatcher).to receive(:dispatch).with(
      Events::Types::MESSAGE_UPDATED, kind_of(Time), hash_including(message: have_attributes(id: other_message.id))
    ).once

    ActiveStorage::AnalyzeJob.perform_now(blob)
  end

  it 'does not broadcast an avatar as a message attachment' do
    avatar_blob = ActiveStorage::Blob.create_and_upload!(
      io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png'
    )
    create(:contact).avatar.attach(avatar_blob)
    expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

    ActiveStorage::AnalyzeJob.perform_now(avatar_blob)

    expect(avatar_blob.reload.metadata).to include('width' => 256, 'height' => 256)
  end

  it 'does not broadcast for an unattached blob' do
    unattached_blob = ActiveStorage::Blob.create_and_upload!(
      io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png'
    )
    expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

    ActiveStorage::AnalyzeJob.perform_now(unattached_blob)
  end

  it 'finishes analysis without broadcasting after the message is destroyed' do
    analyzed_blob = blob
    message.destroy!
    expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

    expect { ActiveStorage::AnalyzeJob.perform_now(analyzed_blob) }.not_to raise_error
    expect(analyzed_blob.reload).to be_analyzed
  end

  it 'ignores an orphan attachment whose message has disappeared' do
    analyzed_blob = blob
    message.delete
    expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

    expect { ActiveStorage::AnalyzeJob.perform_now(analyzed_blob) }.not_to raise_error
  end

  it 'does not broadcast a message marked as deleted' do
    message.update!(content_attributes: { deleted: true })
    expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

    ActiveStorage::AnalyzeJob.perform_now(blob)
  end

  it 'does not broadcast an image when no analyzer supplies dimensions' do
    allow(ActiveStorage).to receive(:analyzers).and_return([])
    expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

    ActiveStorage::AnalyzeJob.perform_now(blob)

    expect(blob.reload).to be_analyzed
    expect(blob.metadata.values_at('width', 'height')).to eq([nil, nil])
  end

  it 'does not broadcast incomplete dimensions' do
    expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

    blob.update!(metadata: blob.metadata.merge('analyzed' => true, 'width' => 256))
  end

  context 'with a video attachment' do
    let!(:message) { create(:message) }
    let(:attachment) do
      message.attachments.create!(
        account: message.account, file_type: :video,
        file: { io: Rails.root.join('spec/assets/sample.mp4').open, filename: 'sample.mp4', content_type: 'video/mp4' }
      )
    end

    it 'broadcasts dimensions supplied by the video analyzer' do
      video_analyzer = instance_double(ActiveStorage::Analyzer::VideoAnalyzer, metadata: { width: 640, height: 480 })
      allow(ActiveStorage::Analyzer::VideoAnalyzer).to receive(:new).with(blob).and_return(video_analyzer)
      expect(dispatcher).to receive(:dispatch).with(
        Events::Types::MESSAGE_UPDATED, kind_of(Time), hash_including(message: have_attributes(id: message.id))
      ).once do |_event, _time, data|
        expect(data[:message].push_event_data[:attachments]).to include(hash_including(width: 640, height: 480))
      end

      ActiveStorage::AnalyzeJob.perform_now(blob)
    end
  end

  context 'with a PDF attachment' do
    let!(:message) { create(:message) }
    let(:attachment) do
      message.attachments.create!(
        account: message.account, file_type: :file,
        file: { io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'sample.pdf', content_type: 'application/pdf' }
      )
    end

    it 'finishes without broadcasting dimensions' do
      expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

      ActiveStorage::AnalyzeJob.perform_now(blob)

      expect(blob.reload).to be_analyzed
    end
  end

  context 'with an audio attachment' do
    let!(:message) { create(:message) }
    let(:attachment) do
      message.attachments.create!(
        account: message.account, file_type: :audio,
        file: { io: Rails.root.join('spec/assets/sample.mp3').open, filename: 'sample.mp3', content_type: 'audio/mpeg' }
      )
    end

    it 'does not broadcast for duration metadata without dimensions' do
      audio_analyzer = instance_double(ActiveStorage::Analyzer::AudioAnalyzer, metadata: { duration: 2.5 })
      allow(ActiveStorage::Analyzer::AudioAnalyzer).to receive(:new).with(blob).and_return(audio_analyzer)
      expect(dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything, anything)

      ActiveStorage::AnalyzeJob.perform_now(blob)

      expect(blob.reload.metadata).to include('analyzed' => true, 'duration' => 2.5)
    end
  end
end
