class Messages::AudioTranscriptionService
  attr_reader :attachment, :message, :account

  # assistant: true is the Captain assistant reading a customer's voice note to answer; it has no
  # agent in the loop, so only the account switch (not an agent's personal one) gates it.
  def initialize(attachment, assistant: false)
    @attachment = attachment
    @assistant = assistant
    @message = attachment.message
    @account = message&.account
  end

  def perform(manual: false)
    error = preflight_error(manual: manual)
    return { error: error } if error

    attachment.with_lock { perform_locked(manual: manual) }
  rescue Faraday::UnauthorizedError
    Rails.logger.warn('Skipping audio transcription: OpenAI configuration is invalid or disabled (401 Unauthorized).')
    { error: 'OpenAI configuration is invalid or disabled (401)' }
  end

  def quota_preview
    units = Llm::SpeechToTextService.units_for(attachment)
    return { units: units, available: false, reason: 'account_disabled' } if account.audio_transcriptions.blank?

    enabled = account.feature_enabled?('captain_integration') && account.feature_enabled?('captain_tasks') &&
              internal_bag_available_for_preview?
    { units: units, available: enabled, reason: enabled ? nil : 'plan_unavailable' }
  end

  private

  def preflight_error(manual:)
    return 'Message not found' if message.blank?

    error = switch_error(manual)
    return error if error
    return 'Transcription disabled for this inbox' if call_recording_transcription_disabled?
    return 'Audio too large for transcription' if Llm::SpeechToTextService.too_large?(attachment.file&.blob)
  end

  def switch_error(manual)
    return ('feature_disabled' if account.audio_transcriptions.blank?) if manual

    'automatic_transcription_disabled' unless auto_transcription_allowed?
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
      context: {
        audio_duration_seconds: Llm::SpeechToTextService.duration_seconds(attachment),
        conversation_id: message.conversation_id, message_id: message.id
      }
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
    enabled &&= internal_bag_available?(internal_limits) && account.audio_transcriptions.present? &&
                (manual || auto_transcription_allowed?)
    { error: quota_error_reason(enabled, remaining, units), units: units, remaining: remaining }
  end

  def internal_bag_available?(internal_limits)
    account.plan.blank? || account.plan.unlimited_limit?(:captain_internal_calls) ||
      internal_limits[:total_count].present?
  end

  def internal_bag_available_for_preview?
    return true if account.plan&.unlimited_limit?(:captain_internal_calls)

    configured_limit = (account[:limits] || {})['captain_internal'] || account.plan_limit(:captain_internal_calls)
    account.plan.blank? || configured_limit.present?
  end

  def auto_transcription_allowed?
    return account.audio_transcriptions.present? if @assistant

    assignee = message.conversation.assignee
    return false if assignee.blank?
    return false unless attachment.meta&.[]('auto_transcription_assignee_id').to_s == assignee.id.to_s

    account.audio_transcriptions.present? && assignee.auto_transcribe_audio?
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
