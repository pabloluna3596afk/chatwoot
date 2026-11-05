require 'rails_helper'

RSpec.describe Messages::AudioTranscriptionService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:agent) { create(:user, account: account, role: :agent, ui_settings: { auto_transcribe_audio: true }) }
  let(:conversation) { create(:conversation, account: account, assignee: agent) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }
  let(:service) { described_class.new(attachment) }

  before do
    account.enable_features!('captain_integration', 'captain_tasks')
    attachment.update!(meta: (attachment.meta || {}).merge('duration_seconds' => 10))
    attachment.file.attach(
      io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
      filename: 'voice.mp3',
      content_type: 'audio/mpeg'
    )
    # Create required installation configs
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-api-key' }
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_MODEL') { |config| config.value = 'gpt-4o-mini' }

    # Mock usage limits for transcription to be available
    allow(account).to receive(:usage_limits).and_return(
      {
        agents: ChatwootApp.max_limit,
        inboxes: ChatwootApp.max_limit,
        captain: { internal: { current_available: 100 } }
      }
    )
  end

  describe '#quota_preview' do
    it 'checks plan flags and the configured internal bag without loading usage limits' do
      account.update_columns(limits: { captain_internal: 5 }) # rubocop:disable Rails/SkipsModelValidations
      expect(account).not_to receive(:usage_limits)

      expect(service.quota_preview).to eq(units: 1, available: true, reason: nil)
    end

    it 'marks the preview unavailable when no internal bag is configured' do
      expect(account).not_to receive(:usage_limits)

      expect(service.quota_preview).to eq(units: 1, available: false, reason: 'plan_unavailable')
    end

    it 'marks the preview unavailable when the account administrator disabled transcription' do
      account.update!(audio_transcriptions: false)

      expect(service.quota_preview).to eq(units: 1, available: false, reason: 'account_disabled')
    end
  end

  describe '#perform' do
    context 'when captain_integration feature is not enabled' do
      before do
        account.disable_features!('captain_integration')
      end

      it 'returns transcription limit exceeded' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        expect(service.perform).to include(error: 'plan_unavailable')
      end
    end

    context 'when captain_tasks is not enabled' do
      before { account.disable_features!('captain_tasks') }

      it 'does not contact the provider' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        expect(service.perform).to include(error: 'plan_unavailable')
      end
    end

    context 'when the message is a call recording on an inbox with transcription turned off' do
      let(:channel) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      end
      let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: agent) }
      let(:message) { create(:message, account: account, conversation: conversation, inbox: channel.inbox, content_type: 'voice_call') }

      before do
        channel.update!(provider_config: channel.provider_config.merge('transcription_enabled' => false))
        allow(Llm::SpeechToTextService).to receive(:new).and_return(
          instance_double(Llm::SpeechToTextService, perform: 'Voice note transcript', quota_exceeded?: false)
        )
      end

      it 'skips transcription' do
        expect(service.perform).to eq({ error: 'Transcription disabled for this inbox' })
        expect(Llm::SpeechToTextService).not_to have_received(:new)
      end

      # The setting is about call recordings; an ordinary voice note on the same inbox is untouched.
      it 'still transcribes a voice note sent by the contact' do
        message.update!(content_type: 'text')

        expect(service.perform).not_to eq({ error: 'Transcription disabled for this inbox' })
      end
    end

    context 'when transcription is successful' do
      before do
        allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
        allow(service).to receive(:transcribe_audio).and_return('Hello world transcription')
      end

      it 'returns successful transcription' do
        allow(Rails.logger).to receive(:info)
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Hello world transcription' })
        expect(Rails.logger).to have_received(:info).with('Audio transcription successful (25 chars)')
        expect(Rails.logger).not_to have_received(:info).with(include('Hello world transcription'))
      end
    end

    context 'when automatic transcription uses duration-based usage' do
      it 'passes the same started-minute unit cost to the speech service' do
        attachment.update!(meta: (attachment.meta || {}).merge('duration_seconds' => 300))
        speech_service = instance_double(Llm::SpeechToTextService, perform: 'Five-minute transcript', quota_exceeded?: false)
        expect(Llm::SpeechToTextService).to receive(:new).with(
          blob: attachment.file.blob,
          account: account,
          units: 5
        ).and_return(speech_service)

        result = service.perform

        expect(result).to eq({ success: true, transcriptions: 'Five-minute transcript' })
      end
    end

    context 'when the internal AI quota is exhausted' do
      before do
        allow(account).to receive(:usage_limits).and_return(captain: { internal: { current_available: 0 } })
      end

      it 'returns the existing limit error without creating a transcription service' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        expect(service.perform).to include(error: 'quota_exhausted')
      end
    end

    context 'when the audio costs more units than remain' do
      before do
        attachment.update!(meta: (attachment.meta || {}).merge('duration_seconds' => 300))
        allow(account).to receive(:usage_limits).and_return(captain: { internal: { current_available: 4 } })
      end

      it 'returns the unit cost and remaining quota without contacting the provider' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        expect(service.perform(manual: true)).to include(
          error: 'quota_insufficient',
          quota: { units: 5, remaining: 4, reason: 'quota_insufficient' }
        )
      end
    end

    context 'when quota is exhausted after the pre-check' do
      before do
        allow(account).to receive(:usage_limits).and_return(captain: { internal: { current_available: 100 } })
        allow(Llm::SpeechToTextService).to receive(:new).and_return(
          instance_double(Llm::SpeechToTextService, perform: nil, quota_exceeded?: true)
        )
      end

      it 'returns the existing limit error shape' do
        expect(service.perform).to include(error: 'quota_exhausted')
      end
    end

    context 'when audio transcriptions are disabled' do
      before do
        account.update!(audio_transcriptions: false)
      end

      it 'rejects automatic transcription before contacting the provider' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        result = service.perform
        expect(result).to include(error: 'automatic_transcription_disabled')
      end

      it 'rejects manual transcription with a clear feature-disabled error' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        expect(service.perform(manual: true)).to eq(error: 'feature_disabled')
      end
    end

    context 'when automatic transcription is not enabled for the assigned agent' do
      before { agent.update!(ui_settings: {}) }

      it 'does not contact the provider' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        expect(service.perform).to eq(error: 'automatic_transcription_disabled')
      end

      it 'still allows manual transcription when the account feature is enabled' do
        allow(service).to receive(:transcribe_audio).and_return('Manually requested transcript')

        expect(service.perform(manual: true)).to eq(
          success: true,
          transcriptions: 'Manually requested transcript'
        )
      end
    end

    context 'when the conversation has no assigned agent' do
      before { conversation.update!(assignee: nil) }

      it 'does not contact the provider' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        expect(service.perform).to eq(error: 'automatic_transcription_disabled')
      end
    end

    context 'when the Captain assistant reads a voice note on an unassigned conversation' do
      let(:service) { described_class.new(attachment, assistant: true) }

      before do
        conversation.update!(assignee: nil)
        allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
        allow(service).to receive(:transcribe_audio).and_return('Hola')
      end

      it 'transcribes without needing an agent switch' do
        expect(service.perform).to eq({ success: true, transcriptions: 'Hola' })
      end

      it 'still requires the account switch' do
        account.update!(audio_transcriptions: false)

        expect(service.perform).to eq(error: 'automatic_transcription_disabled')
      end
    end

    context 'when the conversation is reassigned after the audio arrives' do
      before do
        attachment.update!(meta: (attachment.meta || {}).merge('auto_transcription_assignee_id' => agent.id))
        conversation.update!(assignee: create(:user, account: account, role: :agent, ui_settings: { auto_transcribe_audio: true }))
      end

      it 'does not transcribe an audio created for the previous assignee' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        expect(service.perform).to eq(error: 'automatic_transcription_disabled')
      end
    end

    context 'when attachment already has transcribed text' do
      before do
        attachment.update!(meta: (attachment.meta || {}).merge('transcribed_text' => 'Existing transcription'))
        allow(account).to receive(:usage_limits).and_return(captain: { internal: { current_available: 0 } })
      end

      it 'returns existing transcription without calling API' do
        expect(Llm::SpeechToTextService).not_to receive(:new)

        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Existing transcription' })
      end
    end

    context 'when the audio exceeds the transcription byte limit' do
      before do
        attachment.file.attach(
          io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
          filename: 'large.mp3',
          content_type: 'audio/mpeg'
        )
        allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
        allow(attachment.file.blob).to receive(:byte_size).and_return(Llm::SpeechToTextService::BYTE_LIMIT + 1)
      end

      it 'returns an error without transcribing' do
        expect(service).not_to receive(:transcribe_audio)
        expect(service.perform).to eq({ error: 'Audio too large for transcription' })
      end
    end
  end
end
