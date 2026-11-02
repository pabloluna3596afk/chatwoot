# Blob-in, text-out audio transcription shared by voice-note attachments
# (Messages::AudioTranscriptionService) and voice-call recordings
# (Voice::CallTranscriptionService).
class Llm::SpeechToTextService < Llm::LegacyBaseOpenAiService
  include Integrations::LlmInstrumentation

  # OpenAI's transcription endpoint hard limit is 25 MB *decimal* (25_000_000), not
  # binary (25.megabytes = 26_214_400) — using the binary form leaks the 25.0–26.2 MB
  # range to the API as 413s. Long audio (~70+ min Opus) keeps the source audio but
  # skips transcription.
  BYTE_LIMIT = 25_000_000

  attr_reader :blob, :account, :transcription_model

  USAGE_BUCKET = :captain_responses
  USAGE_FEATURE = 'audio_transcription'.freeze

  # Transcription runs on Captain's OpenAI credentials and consumes its response credits.
  def self.available_for?(account)
    return false unless account.feature_enabled?('captain_integration')
    return false if account.audio_transcriptions.blank?

    account.usage_limits[:captain][:responses][:current_available].positive?
  end

  def self.too_large?(blob)
    blob.present? && blob.byte_size > BYTE_LIMIT
  end

  def initialize(blob:, account:)
    super()
    @blob = blob
    @account = account
    @transcription_model = Llm::FeatureRouter.resolve(feature: 'audio_transcription', account: account)[:model]
  end

  def perform
    @usage_reservation_id = reserve_usage
    return if @usage_reservation_id == false

    temp_file_path = fetch_audio_file
    transcribed_text = nil

    File.open(temp_file_path, 'rb') do |file|
      transcribed_text = transcribe_with_usage(file, temp_file_path)['text']
    end

    if transcribed_text.present?
      account.finish_captain_ai_usage!(bucket: USAGE_BUCKET, reservation_id: @usage_reservation_id) if @usage_reservation_id
      @usage_reservation_id = nil
    else
      release_usage
    end
    transcribed_text
  rescue StandardError
    release_usage
    raise
  ensure
    FileUtils.rm_f(temp_file_path) if temp_file_path.present?
  end

  def quota_exceeded?
    @usage_reservation_id == false
  end

  private

  def reserve_usage
    return unless reservation_receipt_required?

    reservation_id = SecureRandom.uuid
    return false unless account.reserve_captain_ai_usage!(bucket: USAGE_BUCKET, reservation_id: reservation_id)

    reservation_id
  end

  def reservation_receipt_required?
    captain_limits = account.usage_limits[:captain]
    account.current_usage_period.present? && captain_limits.dig(:responses, :total_count).present?
  end

  def release_usage
    return unless @usage_reservation_id

    account.release_captain_ai_usage!(bucket: USAGE_BUCKET, reservation_id: @usage_reservation_id)
    @usage_reservation_id = nil
  end

  def transcribe_with_usage(file, temp_file_path)
    params = instrumentation_params(temp_file_path)
    Llm::UsageContext.with(
      account: account, bucket: USAGE_BUCKET, feature: USAGE_FEATURE,
      reservation_id: @usage_reservation_id,
      context: { reservation_required: @usage_reservation_id.present?, required_gate: 'captain_integration' }
    ) do
      with_usage_recording(params) do
        instrument_audio_transcription(params) do
          # temperature: 0.0 minimises hallucinations on silence / near-silent
          # audio; non-zero values trigger spiraling repeats.
          transcribe_audio(file)
        end
      end
    end
  end

  def transcribe_audio(file)
    @client.audio.transcribe(
      parameters: {
        model: transcription_model,
        file: file,
        temperature: 0.0
      }
    )
  end

  def fetch_audio_file
    temp_dir = Rails.root.join('tmp/uploads/audio-transcriptions')
    FileUtils.mkdir_p(temp_dir)
    temp_file_name = "#{blob.key}-#{blob.filename}"

    if blob.filename.extension_without_delimiter.blank?
      extension = extension_from_content_type(blob.content_type)
      temp_file_name = "#{temp_file_name}.#{extension}" if extension.present?
    end

    temp_file_path = File.join(temp_dir, temp_file_name)

    File.open(temp_file_path, 'wb') do |file|
      blob.open do |blob_file|
        IO.copy_stream(blob_file, file)
      end
    end

    temp_file_path
  end

  def extension_from_content_type(content_type)
    subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
    return if subtype.blank?

    {
      'x-m4a' => 'm4a',
      'x-wav' => 'wav',
      'x-mp3' => 'mp3'
    }.fetch(subtype, subtype)
  end

  def instrumentation_params(file_path)
    {
      span_name: 'llm.messages.audio_transcription',
      model: transcription_model,
      provider: 'openai',
      account_id: account&.id,
      feature_name: USAGE_FEATURE,
      file_path: file_path
    }
  end
end
