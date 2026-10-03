require 'rails_helper'

describe Whatsapp::TemplateHeaderMedia do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:phone_number_id) { channel.provider_config['phone_number_id'].to_s }
  let(:png_path) { Rails.root.join('spec/assets/avatar.png') }

  def upload(path, type)
    ActionDispatch::Http::UploadedFile.new(tempfile: File.open(path), filename: File.basename(path), type: type)
  end

  def stored_blob(account_id: channel.account_id)
    ActiveStorage::Blob.create_and_upload!(
      io: png_path.open, filename: 'avatar.png', content_type: 'image/png', metadata: { 'account_id' => account_id }
    )
  end

  describe '.validate!' do
    it 'accepts what Meta accepts in each header' do
      expect { described_class.validate!('IMAGE', 'image/png', 5.megabytes) }.not_to raise_error
      expect { described_class.validate!('VIDEO', 'video/mp4', 16.megabytes) }.not_to raise_error
      expect { described_class.validate!('DOCUMENT', 'application/pdf', 100.megabytes) }.not_to raise_error
    end

    it 'refuses another type, too big a file, an empty one and an unknown format' do
      expect { described_class.validate!('IMAGE', 'image/gif', 10) }.to raise_error(described_class::InvalidFile) { |e| expect(e.reason).to eq('invalid_type') }
      expect { described_class.validate!('IMAGE', 'image/png', 5.megabytes + 1) }.to raise_error(described_class::InvalidFile) { |e| expect(e.reason).to eq('too_large') }
      expect { described_class.validate!('VIDEO', 'video/mp4', 16.megabytes + 1) }.to raise_error(described_class::InvalidFile) { |e| expect(e.reason).to eq('too_large') }
      expect { described_class.validate!('IMAGE', 'image/png', 0) }.to raise_error(described_class::InvalidFile) { |e| expect(e.reason).to eq('empty') }
      expect { described_class.validate!('AUDIO', 'audio/mpeg', 10) }.to raise_error(described_class::InvalidFile) { |e| expect(e.reason).to eq('invalid_format') }
    end
  end

  describe '.store_and_upload!' do
    it 'keeps a copy of the file and returns what to save with the template' do
      allow(Whatsapp::MediaUploadService).to receive(:upload_blob!).and_return('media_1')

      header = described_class.store_and_upload!(channel, format: 'IMAGE', file: upload(png_path, 'image/png'))

      expect(header).to include('media_id' => 'media_1', 'media_type' => 'image', 'media_name' => 'avatar.png',
                                'media_phone_number_id' => phone_number_id)
      expect(header['media_uploaded_at']).to be_present
      expect(header['media_url']).to be_present
      expect(ActiveStorage::Blob.find_signed(header['media_blob']).metadata).to include('account_id' => channel.account_id)
    end

    it 'does not upload a file the header does not accept' do
      allow(Whatsapp::MediaUploadService).to receive(:upload_blob!)

      expect { described_class.store_and_upload!(channel, format: 'VIDEO', file: upload(png_path, 'image/png')) }
        .to raise_error(described_class::InvalidFile)
      expect(Whatsapp::MediaUploadService).not_to have_received(:upload_blob!)
    end
  end

  describe '.media_id_for' do
    let(:blob) { stored_blob }
    let(:header) do
      { 'media_id' => 'old', 'media_blob' => blob.signed_id, 'media_phone_number_id' => phone_number_id,
        'media_uploaded_at' => 2.days.ago.iso8601 }
    end

    before { allow(Whatsapp::MediaUploadService).to receive(:upload_blob!).and_return('new') }

    it 'is nil without a media_id (the link is used)' do
      expect(described_class.media_id_for(channel, header.except('media_id'))).to be_nil
    end

    it 'keeps a recent id of this number' do
      expect(described_class.media_id_for(channel, header)).to eq('old')
      expect(Whatsapp::MediaUploadService).not_to have_received(:upload_blob!)
    end

    it 'uploads the stored copy again once the id is older than 25 days' do
      header['media_uploaded_at'] = 26.days.ago.iso8601

      expect(described_class.media_id_for(channel, header)).to eq('new')
      expect(Whatsapp::MediaUploadService).to have_received(:upload_blob!).with(channel, blob)
    end

    it 'uploads the stored copy through the number it is sent from' do
      header['media_phone_number_id'] = 'another-number'

      expect(described_class.media_id_for(channel, header)).to eq('new')
    end

    it 'ignores a copy stored by another account' do
      header['media_blob'] = stored_blob(account_id: channel.account_id + 1).signed_id
      header['media_uploaded_at'] = 26.days.ago.iso8601
      header['media_phone_number_id'] = 'another-number'

      expect(described_class.media_id_for(channel, header)).to be_nil
      expect(Whatsapp::MediaUploadService).not_to have_received(:upload_blob!)
    end

    it 'falls back to the link when the refresh fails' do
      header['media_uploaded_at'] = 26.days.ago.iso8601
      allow(Whatsapp::MediaUploadService).to receive(:upload_blob!).and_raise(Whatsapp::MediaUploadService::UploadError, 'boom')

      expect(described_class.media_id_for(channel, header)).to be_nil
    end
  end
end
