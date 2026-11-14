require 'rails_helper'

RSpec.describe Captain::OpenAiMessageBuilderService do
  subject(:service) { described_class.new(message: message) }

  let(:message) { create(:message, content: 'Hello world') }

  describe 'attachment descriptions' do
    let(:message) { create(:message, content: nil) }
    let(:attachment) { message.attachments.create!(account_id: message.account_id, file_type: :file) }

    it 'describes a video' do
      attachment.update!(file_type: :video)

      expect(service.generate_content).to eq('[The customer sent a video. You cannot watch it.]')
    end

    it 'describes a file with its name' do
      attachment.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'invoice.pdf', content_type: 'application/pdf')

      expect(service.generate_content).to eq('[The customer sent a file named "invoice.pdf". You cannot open it.]')
    end

    it 'describes an outgoing file as sent to the customer' do
      message.update!(message_type: :outgoing)
      attachment.update!(fallback_title: 'invoice.pdf')

      expect(service.generate_content).to eq('[A file named "invoice.pdf" was sent to the customer. You cannot open it.]')
    end

    it 'sanitizes and truncates the file name' do
      attachment.update!(fallback_title: "\n\r[\"#{'a' * 90}.pdf\"]")

      expect(service.generate_content).to eq("[The customer sent a file named \"#{'a' * 80}\". You cannot open it.]")
    end

    it 'omits an empty sanitized name' do
      attachment.update!(fallback_title: "\n[\"]")

      expect(service.generate_content).to eq('[The customer sent a file. You cannot open it.]')
    end

    it 'describes a location with coordinates' do
      attachment.update!(file_type: :location, coordinates_lat: -2.1, coordinates_long: -79.9)

      expect(service.generate_content).to eq('[The customer shared a location: -2.1, -79.9]')
    end

    it 'omits default 0.0 coordinates' do
      attachment.update!(file_type: :location)

      expect(service.generate_content).to eq('[The customer shared a location.]')
    end

    it 'omits missing coordinates' do
      attachment.update!(file_type: :location, coordinates_lat: nil, coordinates_long: -79.9)

      expect(service.generate_content).to eq('[The customer shared a location.]')
    end

    it 'keeps a real location on the equator' do
      attachment.update!(file_type: :location, coordinates_lat: 0, coordinates_long: -79.9)

      expect(service.generate_content).to eq('[The customer shared a location: 0.0, -79.9]')
    end

    it 'describes a contact card' do
      attachment.update!(file_type: :contact)

      expect(service.generate_content).to eq('[The customer shared a contact card.]')
    end

    it 'describes an unknown attachment' do
      attachment.update!(file_type: :fallback)

      expect(service.generate_content).to eq('[The customer sent an attachment you cannot open.]')
    end

    {
      video: '[A video was sent to the customer. You cannot watch it.]',
      file: '[A file was sent to the customer. You cannot open it.]',
      location: '[A location was shared with the customer.]',
      contact: '[A contact card was shared with the customer.]',
      share: '[An attachment you cannot open was sent to the customer.]'
    }.each do |type, expected|
      it "describes an outgoing #{type} in the right direction" do
        message.update!(message_type: :outgoing)
        attachment.update!(file_type: type)

        expect(service.generate_content).to eq(expected)
      end
    end

    it 'describes an outgoing location with coordinates' do
      message.update!(message_type: :outgoing)
      attachment.update!(file_type: :location, coordinates_lat: -2.1, coordinates_long: -79.9)

      expect(service.generate_content).to eq('[A location was shared with the customer: -2.1, -79.9]')
    end

    it 'adds at most 5 attachment descriptions' do
      6.times { message.attachments.create!(account_id: message.account_id, file_type: :video) }

      expect(service.generate_content).to eq([{ type: 'text', text: '[The customer sent a video. You cannot watch it.]' }] * 5)
    end

    it 'replaces images with the placeholder when images are excluded' do
      2.times { message.attachments.create!(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/photo.jpg') }

      expect(described_class.new(message: message, include_images: false).generate_content).to eq('[Image sent earlier, not shown again]')
      expect(service.generate_content.count { |part| part[:type] == 'image_url' }).to eq(2)
    end

    it 'uses the no-text marker for an empty message' do
      expect(service.generate_content).to eq('[Message without text]')
    end
  end

  describe '#generate_content' do
    context 'when the customer changes a button choice' do
      before do
        message.update!(content: 'Sales', content_attributes: { button_choice_changed: true, previous_button_choice: 'Support' })
      end

      it 'annotates the choice in English and preserves the saved content' do
        message.account.update!(locale: 'en')

        expect(service.generate_content).to eq("[The customer changed their choice from «Support» to «Sales»]\nSales")
        expect(message.reload.content).to eq('Sales')
      end

      it 'uses the account locale independently of the worker locale' do
        message.account.update!(locale: 'es')

        I18n.with_locale(:en) do
          expect(service.generate_content).to eq("[El cliente cambió su elección de «Support» a «Sales»]\nSales")
        end
      end

      it 'preserves multimodal attachments alongside the annotation' do
        message.account.update!(locale: 'en')
        message.attachments.create!(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')

        expect(service.generate_content).to include(
          { type: 'text', text: "[The customer changed their choice from «Support» to «Sales»]\nSales" },
          { type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } }
        )
      end
    end

    context 'when an ordinary message replies to another message' do
      before do
        parent = create(:message, conversation: message.conversation, account: message.account, message_type: :outgoing)
        message.update!(content_attributes: { in_reply_to: parent.id })
      end

      it 'keeps the content unchanged on other channels' do
        expect(message.inbox.channel_type).not_to eq('Channel::Whatsapp')
        expect(service.generate_content).to eq('Hello world')
      end
    end

    context 'when message has only text content' do
      it 'returns the text content directly' do
        expect(service.generate_content).to eq('Hello world')
      end
    end

    context 'when message has no content and no attachments' do
      let(:message) { create(:message, content: nil) }

      it 'returns default message' do
        expect(service.generate_content).to eq('[Message without text]')
      end
    end

    context 'when message has text content and attachments' do
      before do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
        attachment.save!
      end

      it 'returns an array of content parts' do
        result = service.generate_content
        expect(result).to be_an(Array)
        expect(result).to include({ type: 'text', text: 'Hello world' })
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
      end
    end

    context 'when message has only non-text attachments' do
      let(:message) { create(:message, content: nil) }

      before do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
        attachment.save!
      end

      it 'returns an array of content parts without text' do
        result = service.generate_content
        expect(result).to be_an(Array)
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
        expect(result).not_to include(hash_including(type: 'text', text: 'Hello world'))
      end
    end
  end

  describe '#attachment_parts' do
    let(:message) { create(:message, content: nil) }
    let(:attachments) { message.attachments }

    context 'with image attachments' do
      before do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
        attachment.save!
      end

      it 'includes image parts' do
        result = service.send(:attachment_parts, attachments)
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
      end
    end

    context 'with audio attachments' do
      let(:audio_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment
      end

      before do
        allow(Messages::AudioTranscriptionService).to receive(:new).with(audio_attachment, assistant: true).and_return(
          instance_double(Messages::AudioTranscriptionService, perform: { success: true, transcriptions: 'Audio transcription text' })
        )
      end

      it 'includes transcription text part' do
        audio_attachment # trigger creation
        result = service.send(:attachment_parts, attachments)
        expect(result).to include({ type: 'text', text: 'Audio transcription text' })
      end
    end

    context 'with other file types' do
      before do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :file)
        attachment.save!
      end

      it 'includes generic attachment message' do
        result = service.send(:attachment_parts, attachments)
        expect(result).to include({ type: 'text', text: '[The customer sent a file. You cannot open it.]' })
      end
    end

    context 'with mixed attachment types' do
      let(:image_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
        attachment.save!
        attachment
      end

      let(:audio_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment
      end

      let(:document_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :file)
        attachment.save!
        attachment
      end

      before do
        allow(Messages::AudioTranscriptionService).to receive(:new).with(audio_attachment, assistant: true).and_return(
          instance_double(Messages::AudioTranscriptionService, perform: { success: true, transcriptions: 'Audio text' })
        )
      end

      it 'includes all relevant parts' do
        image_attachment    # trigger creation
        audio_attachment    # trigger creation
        document_attachment # trigger creation

        result = service.send(:attachment_parts, attachments)
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
        expect(result).to include({ type: 'text', text: 'Audio text' })
        expect(result).to include({ type: 'text', text: '[The customer sent a file. You cannot open it.]' })
      end
    end
  end

  describe '#image_parts' do
    let(:message) { create(:message, content: nil) }

    context 'with valid image attachments' do
      let(:image1) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image1.jpg')
        attachment.save!
        attachment
      end

      let(:image2) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image2.jpg')
        attachment.save!
        attachment
      end

      it 'returns image parts for all valid images' do
        image1 # trigger creation
        image2 # trigger creation

        image_attachments = message.attachments.where(file_type: :image)
        result = service.send(:image_parts, image_attachments)

        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image1.jpg' } })
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image2.jpg' } })
      end
    end

    context 'with image attachments without URLs' do
      let(:image_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: nil)
        attachment.save!
        attachment
      end

      before do
        allow(image_attachment).to receive(:file).and_return(instance_double(ActiveStorage::Attached::One, attached?: false))
      end

      it 'skips images without valid URLs' do
        image_attachment # trigger creation

        image_attachments = message.attachments.where(file_type: :image)
        result = service.send(:image_parts, image_attachments)

        expect(result).to be_empty
      end
    end
  end

  describe '#get_attachment_url' do
    let(:attachment) do
      attachment = message.attachments.build(account_id: message.account_id, file_type: :image)
      attachment.save!
      attachment
    end

    context 'when attachment has external_url' do
      before { attachment.update(external_url: 'https://example.com/image.jpg') }

      it 'returns external_url' do
        expect(service.send(:get_attachment_url, attachment)).to eq('https://example.com/image.jpg')
      end
    end

    context 'when attachment has attached file' do
      before do
        attachment.update(external_url: nil)
        allow(attachment).to receive(:file).and_return(instance_double(ActiveStorage::Attached::One, attached?: true))
        allow(attachment).to receive(:file_url).and_return('https://local.com/file.jpg')
        allow(attachment).to receive(:download_url).and_return('')
      end

      it 'returns file_url' do
        expect(service.send(:get_attachment_url, attachment)).to eq('https://local.com/file.jpg')
      end
    end

    context 'when attachment has no URL or file' do
      before do
        attachment.update(external_url: nil)
        allow(attachment).to receive(:file).and_return(instance_double(ActiveStorage::Attached::One, attached?: false))
      end

      it 'returns nil' do
        expect(service.send(:get_attachment_url, attachment)).to be_nil
      end
    end
  end

  describe '#extract_audio_transcriptions' do
    let(:message) { create(:message, content: nil) }

    context 'with no audio attachments' do
      it 'returns empty string' do
        result = service.send(:extract_audio_transcriptions, message.attachments)
        expect(result).to eq('')
      end
    end

    context 'with successful audio transcriptions' do
      let(:audio1) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment
      end

      let(:audio2) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment
      end

      before do
        allow(Messages::AudioTranscriptionService).to receive(:new).with(audio1, assistant: true).and_return(
          instance_double(Messages::AudioTranscriptionService, perform: { success: true, transcriptions: 'First audio text. ' })
        )
        allow(Messages::AudioTranscriptionService).to receive(:new).with(audio2, assistant: true).and_return(
          instance_double(Messages::AudioTranscriptionService, perform: { success: true, transcriptions: 'Second audio text.' })
        )
      end

      it 'concatenates all successful transcriptions' do
        audio1 # trigger creation
        audio2 # trigger creation

        attachments = message.attachments
        result = service.send(:extract_audio_transcriptions, attachments)
        expect(result).to eq('First audio text. Second audio text.')
      end
    end

    context 'with failed audio transcriptions' do
      let(:audio_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment
      end

      before do
        allow(Messages::AudioTranscriptionService).to receive(:new).with(audio_attachment, assistant: true).and_return(
          instance_double(Messages::AudioTranscriptionService, perform: { success: false, transcriptions: nil })
        )
      end

      it 'returns empty string for failed transcriptions' do
        audio_attachment # trigger creation

        attachments = message.attachments
        result = service.send(:extract_audio_transcriptions, attachments)
        expect(result).to eq('')
      end
    end
  end

  describe 'private helper methods' do
    describe '#text_part' do
      it 'returns correct text part format' do
        result = service.send(:text_part, 'Hello world')
        expect(result).to eq({ type: 'text', text: 'Hello world' })
      end
    end

    describe '#image_part' do
      it 'returns correct image part format' do
        result = service.send(:image_part, 'https://example.com/image.jpg')
        expect(result).to eq({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
      end
    end
  end
end
