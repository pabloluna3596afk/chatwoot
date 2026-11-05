require 'rails_helper'

RSpec.describe Llm::SpeechToTextService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }
  let(:service) { described_class.new(blob: attachment.file.blob, account: account) }

  before do
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-api-key' }
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_MODEL') { |config| config.value = 'gpt-4o-mini' }

    attachment.file.attach(
      io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
      filename: 'speech',
      content_type: 'audio/mpeg'
    )
  end

  describe '.available_for?' do
    before do
      allow(account).to receive(:usage_limits).and_return(
        {
          agents: ChatwootApp.max_limit,
          inboxes: ChatwootApp.max_limit,
          captain: { internal: { current_available: 100 } }
        }
      )
    end

    it 'is false when the captain_integration feature is disabled' do
      account.disable_features!('captain_integration')

      expect(described_class.available_for?(account)).to be(false)
    end

    it 'is false when audio transcriptions are disabled on the account' do
      account.enable_features!('captain_integration', 'captain_tasks')
      account.update!(audio_transcriptions: false)

      expect(described_class.available_for?(account)).to be(false)
    end

    it 'is false when no internal AI credits are available' do
      account.enable_features!('captain_integration', 'captain_tasks')
      allow(account).to receive(:usage_limits).and_return(captain: { internal: { current_available: 0 } })

      expect(described_class.available_for?(account)).to be(false)
    end

    it 'is false when the assigned plan has no internal action bag' do
      put_account_on_plan(account, captain_internal_calls: nil)
      account.enable_features!('captain_integration', 'captain_tasks')

      expect(described_class.available_for?(account)).to be(false)
    end

    it 'is true when the feature, setting and credits are all present' do
      account.enable_features!('captain_integration', 'captain_tasks')

      expect(described_class.available_for?(account)).to be(true)
    end

    it 'uses internal availability even when the response pool is exhausted' do
      account.enable_features!('captain_integration', 'captain_tasks')
      allow(account).to receive(:usage_limits).and_return(
        captain: { internal: { current_available: 1 }, responses: { current_available: 0 } }
      )

      expect(described_class.available_for?(account)).to be(true)
    end
  end

  describe '.too_large?' do
    it 'is false when the blob is missing' do
      expect(described_class.too_large?(nil)).to be(false)
    end

    it 'is true beyond the byte limit' do
      allow(attachment.file.blob).to receive(:byte_size).and_return(described_class::BYTE_LIMIT + 1)

      expect(described_class.too_large?(attachment.file.blob)).to be(true)
    end
  end

  describe '.units_for' do
    it 'charges one unit for ten seconds and rounds started minutes up' do
      attachment.update!(meta: { duration_seconds: 10 })
      expect(described_class.units_for(attachment)).to eq(1)

      attachment.update!(meta: { duration_seconds: 61 })
      expect(described_class.units_for(attachment)).to eq(2)
    end

    it 'charges five units for five minutes' do
      attachment.update!(meta: { duration_seconds: 300 })

      expect(described_class.units_for(attachment)).to eq(5)
    end

    it 'estimates duration from blob size when metadata is unavailable' do
      allow(attachment.file.blob).to receive(:byte_size).and_return(4_000 * 61)

      expect(described_class.units_for(attachment)).to eq(2)
    end

    it 'estimates duration from blob size when metadata is invalid' do
      attachment.update!(meta: { duration_seconds: 'invalid' })
      allow(attachment.file.blob).to receive(:byte_size).and_return(4_000 * 300)

      expect(described_class.units_for(attachment)).to eq(5)
    end

    it 'caps the estimated duration at the maximum transcribable size' do
      allow(attachment.file.blob).to receive(:byte_size).and_return(described_class::BYTE_LIMIT * 2)

      expect(described_class.units_for(attachment)).to eq(described_class::MAX_ESTIMATED_DURATION_UNITS)
    end
  end

  describe '#fetch_audio_file' do
    it 'adds extension from content type when filename has no extension' do
      temp_file_path = service.send(:fetch_audio_file)

      expect(File.extname(temp_file_path)).to eq('.mpeg')
    ensure
      FileUtils.rm_f(temp_file_path) if temp_file_path.present?
    end
  end

  describe '#perform' do
    let(:audio_api) { double('audio_api') } # rubocop:disable RSpec/VerifiedDoubles
    let(:audio_file_path) { Rails.root.join('tmp/speech_to_text_service_spec.mp3').to_s }

    before do
      File.binwrite(audio_file_path, 'audio')
      allow(service).to receive(:fetch_audio_file).and_return(audio_file_path)
      allow(service.client).to receive(:audio).and_return(audio_api)
    end

    after do
      FileUtils.rm_f(audio_file_path)
    end

    it 'uses the audio transcription feature model' do
      expect(audio_api).to receive(:transcribe).with(
        parameters: hash_including(model: 'gpt-transcribe', temperature: 0.0)
      ).and_return({ 'text' => 'Audio transcript' })

      expect(service.perform).to eq('Audio transcript')
    end

    it 'reserves and charges one internal AI credit when text comes back' do
      put_account_on_plan(account, captain_internal_calls: 1)
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => 'Audio transcript' })

      service.perform

      expect(account.reload.usage_limits.dig(:captain, :internal, :consumed)).to eq(1)
      expect(captain_responses_used(account)).to eq(0)
      expect(AiUsageEvent.where(account: account, feature: 'audio_transcription', bucket: 'internal', status: 'ok').count).to eq(1)
    end

    it 'charges five internal credits for a five-minute audio' do
      put_account_on_plan(account, captain_internal_calls: 5)
      attachment.update!(meta: { duration_seconds: 300 })
      service = described_class.new(blob: attachment.file.blob, account: account, units: described_class.units_for(attachment))
      allow(service).to receive(:fetch_audio_file).and_return(audio_file_path)
      allow(service.client).to receive(:audio).and_return(audio_api)
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => 'Audio transcript' })

      expect(service.perform).to eq('Audio transcript')
      expect(account.reload.usage_limits.dig(:captain, :internal, :consumed)).to eq(5)
    end

    it 'does not consume a credit when the transcription is blank and releases the reservation' do
      put_account_on_plan(account, captain_internal_calls: 1)
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => '' })

      service.perform

      expect(account.reload.usage_limits.dig(:captain, :internal, :consumed)).to eq(0)
      expect(AiUsageReservation.joins(:account_plan_usage).where(account_plan_usages: { account_id: account.id }, released_at: nil)).to be_empty
    end

    it 'rejects the request before the provider when the internal limit is zero' do
      put_account_on_plan(account, captain_internal_calls: 0)

      expect(audio_api).not_to receive(:transcribe)
      expect(service.perform).to be_nil
      expect(service.quota_exceeded?).to be(true)
      expect(account.reload.usage_limits.dig(:captain, :internal, :consumed)).to eq(0)
      expect(account.reload.usage_limits.dig(:captain, :responses, :consumed)).to eq(0)
    end

    it 'rejects a concurrent request before calling the provider when the last credit is reserved' do
      put_account_on_plan(account, captain_internal_calls: 1)
      second_service = described_class.new(blob: attachment.file.blob, account: account)
      allow(second_service).to receive(:fetch_audio_file).and_return(audio_file_path)
      allow(service.client).to receive(:audio).and_return(audio_api)
      allow(second_service.client).to receive(:audio).and_return(audio_api)
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => 'Audio transcript' })

      expect(service.perform).to eq('Audio transcript')
      expect(second_service.perform).to be_nil
      expect(second_service.quota_exceeded?).to be(true)
      expect(audio_api).to have_received(:transcribe).once
      expect(account.reload.usage_limits.dig(:captain, :internal, :consumed)).to eq(1)
    end

    it 'releases the reservation when the provider fails so a retry can charge once' do
      put_account_on_plan(account, captain_internal_calls: 1)
      allow(audio_api).to receive(:transcribe).and_raise(Faraday::ConnectionFailed, 'provider unavailable')

      expect { service.perform }.to raise_error(Faraday::ConnectionFailed)
      expect(account.reload.usage_limits.dig(:captain, :internal, :consumed)).to eq(0)

      File.binwrite(audio_file_path, 'audio')
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => 'Audio transcript' })
      expect(service.perform).to eq('Audio transcript')
      expect(account.reload.usage_limits.dig(:captain, :internal, :consumed)).to eq(1)
    end

    it 'reserves and releases all duration-based units when the provider fails' do
      put_account_on_plan(account, captain_internal_calls: 5)
      attachment.update!(meta: { duration_seconds: 300 })
      service = described_class.new(blob: attachment.file.blob, account: account, units: 5)
      allow(service).to receive(:fetch_audio_file).and_return(audio_file_path)
      allow(service.client).to receive(:audio).and_return(audio_api)
      allow(audio_api).to receive(:transcribe).and_raise(Faraday::ConnectionFailed, 'provider unavailable')

      expect { service.perform }.to raise_error(Faraday::ConnectionFailed)
      expect(account.reload.usage_limits.dig(:captain, :internal, :consumed)).to eq(0)
      expect(AiUsageReservation.joins(:account_plan_usage).where(account_plan_usages: { account_id: account.id }, released_at: nil)).to be_empty
    end

    it 'transcribes without requiring a receipt when the account has no usage period' do
      allow(audio_api).to receive(:transcribe).and_return({ 'text' => 'Audio transcript' })

      expect(account).not_to receive(:reserve_captain_ai_usage!)
      expect(service.perform).to eq('Audio transcript')
    end
  end
end
