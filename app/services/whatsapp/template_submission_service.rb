class Whatsapp::TemplateSubmissionService
  MAX_REQUESTS = 3
  BACKOFF = [30.seconds, 2.minutes].freeze

  def initialize(submission)
    @submission = submission
    @preloaded = %i[account actor whatsapp_template_draft].filter_map do |name|
      [name, submission.public_send(name)] if submission.association(name).loaded?
    end.to_h
  end

  def perform(refresh: false)
    with_submission_lock do
      @submission.reload
      # Reload mutable intent without discarding the recurring job's batched associations.
      @preloaded.each { |name, record| @submission.public_send("#{name}=", record) }
      process(refresh)
    rescue Whatsapp::TemplateManagementService::Error => e
      handle_meta_error(e)
    rescue Whatsapp::TemplateHeaderHandleService::Error
      defer('upload_failed', retry_permitted: true)
    end
  end

  private

  def process(refresh)
    return if finished?(refresh) || @submission.next_retry_at&.future?

    @channel = destination_channel
    return fail_submission('destination_changed') unless @channel

    @client = Whatsapp::TemplateManagementService.new(@channel, sync_after_change: false)
    return refresh_remote if @submission.status == 'submitted'

    @submission.status == 'submitting' ? create_initial : reconcile
  end

  def finished?(refresh)
    @submission.status == 'failed' || (@submission.status == 'submitted' && !refresh)
  end

  # Session lock spans committed intent writes and HTTP. A worker crash releases it without rolling back the intent.
  def with_submission_lock
    WhatsappTemplateSubmission.connection_pool.with_connection do |connection|
      key = "whatsapp_template_submission/#{@submission.id}"
      sql = WhatsappTemplateSubmission.sanitize_sql_array(['SELECT pg_try_advisory_lock(hashtextextended(?, 0))', key])
      acquired = connection.select_value(sql)
      begin
        yield if acquired
      ensure
        connection.select_value(WhatsappTemplateSubmission.sanitize_sql_array(['SELECT pg_advisory_unlock(hashtextextended(?, 0))', key])) if acquired
      end
    end
  end

  def destination_channel
    channels = @submission.account.whatsapp_channels.select do |channel|
      channel.provider == 'whatsapp_cloud' && channel.provider_config['business_account_id'] == @submission.waba_id
    end
    preferred_id = @submission.snapshot['preferred_channel_id']
    channels.find { |channel| channel.id == preferred_id } || channels.min_by(&:id)
  end

  def create_initial
    @submission.update!(status: 'reconciling', request_count: 1)
    return fail_submission('remote_identity_exists') if remote_candidates.any?

    post_template
  end

  def remote_candidates
    @client.templates(name: @submission.name).select do |entry|
      entry['name'] == @submission.name && entry['language'] == @submission.language
    end
  end

  def reconcile
    @submission.update!(request_count: @submission.request_count + 1)
    candidates = remote_candidates
    if matching_candidate?(candidates)
      complete(candidates.first.symbolize_keys)
    elsif candidates.any?
      @submission.update!(next_retry_at: nil, retry_permitted: false, error_details: { code: 'ambiguous_remote_identity' })
    elsif @submission.retry_permitted && @submission.request_count <= MAX_REQUESTS
      @submission.update!(retry_permitted: false, next_retry_at: nil)
      post_template
    else
      @submission.update!(next_retry_at: nil, retry_permitted: false)
    end
  end

  def matching_candidate?(candidates)
    expected = @submission.snapshot['reconciliation_payload'] || @submission.request_payload
    candidates.one? && @submission.request_payload && Whatsapp::TemplateSubmissionMatcher.matches?(expected, candidates.first)
  end

  def refresh_remote
    previous_status = @submission.remote_status
    result = @client.fetch(@submission.remote_id)
    @submission.with_lock do
      # A webhook received during HTTP is newer than the refresh we started.
      return if @submission.remote_status != previous_status

      @preloaded.each { |name, record| @submission.public_send("#{name}=", record) }
      @submission.update!(remote_status: result.fetch(:status), remote_category: result.fetch(:category),
                          remote_reason: result[:rejected_reason], error_details: {})
      if previous_status != @submission.remote_status
        Whatsapp::TemplateBackgroundTask.publish(@submission)
        Whatsapp::SyncTemplateWabaJob.perform_later(@submission.account_id, @submission.waba_id)
      end
    end
  end

  def post_template
    prepare_request unless @submission.request_payload
    method = @submission.snapshot.fetch('payload').key?('library_template_name') ? :create_from_library : :create
    result = @client.public_send(method, **@submission.request_payload.deep_symbolize_keys)
    complete(result)
  end

  def prepare_request
    payload = @submission.snapshot.fetch('payload').deep_dup
    upload_media(payload) if @submission.media.attached?
    # Write-once wire payload includes the destination's handle, never its credentials.
    @submission.update!(request_payload: payload)
  end

  def upload_media(payload)
    header = payload.fetch('components').find { |component| Whatsapp::TemplateComponentsBuilder::MEDIA_FORMATS.include?(component['format']) }
    return unless header

    blob = @submission.media.blob
    blob.open do |file|
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: blob.filename.to_s, type: blob.content_type)
      header['example'] = { 'header_handle' => [Whatsapp::TemplateHeaderHandleService.new(@channel).upload!(upload)] }
    end
  end

  def complete(result)
    return defer('invalid_meta_response', retry_permitted: false) unless result.values_at(:id, :status, :category).all?(&:present?)

    @submission.with_lock do
      @submission.update!(status: 'submitted', remote_id: result.fetch(:id), remote_status: result.fetch(:status),
                          remote_category: result.fetch(:category), remote_reason: result[:rejected_reason], submitted_at: Time.current,
                          next_retry_at: nil, retry_permitted: false, error_details: {})
      Whatsapp::TemplateBackgroundTask.publish(@submission)
    end
    Whatsapp::SyncTemplateWabaJob.perform_later(@submission.account_id, @submission.waba_id)
  end

  def handle_meta_error(error)
    detail = { code: error.code, detail: error.detail, meta_code: error.meta_code, http_status: error.http_status,
               error_subcode: error.error_subcode, error_user_msg: error.error_user_msg }.compact
    return @submission.update!(error_details: detail) if @submission.status == 'submitted'

    if error.code == 'meta_unreachable'
      defer(error.code, retry_permitted: false, detail: detail)
    elsif error.code == 'rate_limited' || error.http_status.to_i == 429 || error.http_status.to_i >= 500
      defer(error.code, retry_permitted: true, detail: detail)
    else
      fail_submission(error.code, detail)
    end
  end

  def defer(code, retry_permitted:, detail: { code: code })
    delay = BACKOFF.fetch((@submission.request_count - 1).clamp(0, BACKOFF.size - 1))
    exhausted = @submission.request_count >= MAX_REQUESTS
    @submission.update!(status: 'reconciling', error_details: detail, retry_permitted: retry_permitted,
                        next_retry_at: exhausted ? nil : Time.current + delay)
    Whatsapp::SubmitTemplateDraftJob.set(wait: delay).perform_later(@submission.id) unless exhausted
  end

  def fail_submission(code, details = { code: code })
    return @submission.update!(error_details: details) if @submission.status == 'submitted'

    @submission.update!(status: 'failed', error_details: details, retry_permitted: false, next_retry_at: nil)
    Whatsapp::TemplateBackgroundTask.publish(@submission)
  end
end
