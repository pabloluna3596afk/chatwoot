class Messages::AudioTranscriptionService
  attr_reader :attachment, :message, :account

  def initialize(attachment)
    @attachment = attachment
    @message = attachment.message
    @account = message&.account
  end

  def perform(manual: false)
    error = preflight_error
    return { error: error } if error

    attachment.with_lock { perform_locked(manual: manual) }
  rescue Faraday::UnauthorizedError
    Rails.logger.warn('Skipping audio transcription: OpenAI configuration is invalid or disabled (401 Unauthorized).')
    { error: 'OpenAI configuration is invalid or disabled (401)' }
  end

  def quota_preview
    units = Llm::SpeechToTextService.units_for(attachment)
    enabled = account.feature_enabled?('captain_integration') && account.feature_enabled?('captain_tasks') &&
              internal_bag_configured_for_preview?
    { units: units, available: enabled, reason: enabled ? nil : 'plan_unavailable' }
  end

  private

  def preflight_error
    return 'Message not found' if message.blank?
    return 'Transcription disabled for this inbox' if call_recording_transcription_disabled?
    return 'Audio too large for transcription' if Llm::SpeechToTextService.too_large?(attachment.file&.blob)
  end

  def perform_locked(manual:)
    return transcription_response(attachment.meta['transcribed_text']) if attachment.meta&.[]('transcribed_text').present?

    details = quota_details(manual: manual)
    return quota_error(details) if details[:error]

    transcription_response(transcribe_audio(details[:units]))
  end

  def transcription_response(transcriptions)
    return transcriptions if transcriptions.is_a?(Hash)

    Rails.logger.info "Audio transcription successful (#{transcriptions.to_s.length} chars)"
    { success: true, transcriptions: transcriptions }
  end

  # Call recordings honour the inbox's "Transcribe recordings" setting; ordinary voice notes don't.
  def call_recording_transcription_disabled?
    message.voice_call? && !message.inbox.channel.transcription_enabled?
  end

  def transcribe_audio(units)
    service = Llm::SpeechToTextService.new(
      blob: attachment.file.blob, account: account, units: units,
      conversation_id: message.conversation_id, message_id: message.id
    )
    transcribed_text = service.perform
    if service.quota_exceeded?
      details = quota_details(manual: true)
      return quota_error(details[:error] ? details : details.merge(error: 'quota_exhausted'))
    end

    update_transcription(transcribed_text)
    transcribed_text
  end

  def quota_error(details)
    { error: details[:error], quota: details.slice(:units, :remaining).merge(reason: details[:error]) }
  end

  def quota_details(manual:)
    internal_limits = account.usage_limits.dig(:captain, :internal)
    remaining = internal_limits[:current_available].to_i
    units = Llm::SpeechToTextService.units_for(attachment)
    enabled = account.feature_enabled?('captain_integration') && account.feature_enabled?('captain_tasks')
    enabled &&= internal_bag_available?(internal_limits) && automatic_transcription_enabled?(manual)
    { error: quota_error_reason(enabled, remaining, units), units: units, remaining: remaining }
  end

  def internal_bag_available?(internal_limits)
    account.plan.blank? || internal_limits[:total_count].present?
  end

  def internal_bag_configured_for_preview?
    (account[:limits] || {})['captain_internal'].present?
  end

  def automatic_transcription_enabled?(manual)
    manual || account.audio_transcriptions.present?
  end

  def quota_error_reason(enabled, remaining, units)
    return 'plan_unavailable' unless enabled
    return 'quota_exhausted' if remaining <= 0
    return 'quota_insufficient' if remaining < units
  end

  def update_transcription(transcribed_text)
    return if transcribed_text.blank?

    attachment.update!(meta: (attachment.meta || {}).merge('transcribed_text' => transcribed_text))
    message.reload.send_update_event

    return unless ChatwootApp.advanced_search_allowed?

    message.reindex
  end
end
