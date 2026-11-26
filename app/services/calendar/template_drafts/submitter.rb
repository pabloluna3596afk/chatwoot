class Calendar::TemplateDrafts::Submitter
  # A current revision is blocked while a submission is running, under review, or approved/in appeal.
  # Local failures and Meta's rejected/paused/disabled statuses are retryable.
  BLOCKING_STATUSES = %w[submitting reconciling submitted].freeze
  BLOCKING_REMOTE_STATUSES = %w[APPROVED PENDING IN_APPEAL].freeze
  RETRYABLE_REMOTE_STATUSES = %w[REJECTED PAUSED DISABLED].freeze

  def initialize(account:, actor:, functions:, waba_ids:)
    @account = account
    @actor = actor
    @functions = functions
    @waba_ids = waba_ids
  end

  def perform
    targets = resolve_targets
    submissions = []
    skipped = targets[:skipped]
    failed = targets[:failed]

    targets[:ready].each do |target|
      submission = submit(target.fetch(:draft))
      submissions << submission
      failed << result_for(target, submission.error_details['code']) if submission.status == 'failed'
    end

    { submissions: submissions, skipped: skipped, failed: failed }
  end

  private

  def resolve_targets
    entries = @functions.flat_map { |function| resolve_function(function) }
    %i[ready skipped failed].index_with { |key| entries.filter_map { |entry| entry.last if entry.first == key } }
  end

  def resolve_function(function)
    source = source_draft(function)
    @waba_ids.map { |waba_id| resolve_destination(source, function, waba_id) }
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("Calendar template source unavailable (#{e.class})")
    @waba_ids.map { |waba_id| [:failed, result_for({ function: function, waba_id: waba_id }, 'source_unavailable')] }
  end

  def resolve_destination(source, function, waba_id)
    target = { function: function, waba_id: waba_id }
    channel = destination_channel(waba_id)
    draft = destination_draft(source, waba_id, channel)
    return [:skipped, result_for(target, 'name_taken')] if destination_owned_by_another_draft?(draft, source)
    return [:skipped, result_for(target, 'already_submitted')] if already_sent?(latest_submission(draft), draft)

    target[:draft] = draft
    [:ready, target]
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("Calendar template destination unavailable (#{e.class})")
    [:failed, result_for(target, 'destination_unavailable')]
  rescue ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("Calendar template destination race (#{e.class})")
    resolve_destination_race(source, target)
  rescue StandardError => e
    Rails.logger.error("Calendar template destination validation failed (#{e.class}): #{e.message}")
    [:failed, result_for(target, 'submission_failed')]
  end

  def resolve_destination_race(source, target)
    draft = find_destination_draft(source, target.fetch(:waba_id))
    return [:skipped, result_for(target, 'name_taken')] unless draft&.source_draft_id == source.id
    return [:skipped, result_for(target, 'already_submitted')] if already_sent?(latest_submission(draft), draft)

    target[:draft] = draft
    [:ready, target]
  end

  def destination_owned_by_another_draft?(draft, source)
    draft.id != source.id && draft.source_draft_id != source.id
  end

  def source_draft(function)
    saved = (@account.calendar_template_preparation || {}).dig('results', function)
    draft = @account.whatsapp_template_drafts.active.find_by(id: saved&.fetch('draft_id', nil))
    raise ActiveRecord::RecordNotFound unless draft

    draft
  end

  def find_destination_draft(source, waba_id)
    @account.whatsapp_template_drafts.active.find_by(name: source.name, language: source.language, waba_id: waba_id)
  end

  def destination_draft(source, waba_id, channel)
    return source if source.waba_id == waba_id

    find_destination_draft(source, waba_id) || create_destination_draft(source, waba_id, channel)
  end

  def create_destination_draft(source, waba_id, channel)
    attributes = source.attributes.except('id', 'created_at', 'updated_at', 'source_remote_id')
    draft = @account.whatsapp_template_drafts.active.create_or_find_by!(name: source.name, language: source.language, waba_id: waba_id) do |copy|
      copy.assign_attributes(attributes)
      copy.assign_attributes(account: @account, preferred_channel: channel, created_by: @actor, updated_by: @actor,
                             source_draft: source, source_remote_id: nil, lock_version: 0)
    end
    draft.media.attach(source.media.blob) if source.media.attached? && !draft.media.attached?
    draft
  end

  def destination_channel(waba_id)
    @account.whatsapp_channels.where(provider: 'whatsapp_cloud').detect do |channel|
      channel.provider_config['business_account_id'] == waba_id
    end || raise(ActiveRecord::RecordNotFound)
  end

  def latest_submission(draft)
    draft.submissions.where(waba_id: draft.waba_id, language: draft.language).order(revision: :desc).first
  end

  def already_sent?(submission, draft)
    return false unless submission && submission.revision == draft.lock_version
    return false if RETRYABLE_REMOTE_STATUSES.include?(submission.remote_status)

    BLOCKING_STATUSES.include?(submission.status) || BLOCKING_REMOTE_STATUSES.include?(submission.remote_status)
  end

  def submit(draft)
    advance_revision_for_remote_retry(draft)
    Whatsapp::SubmitTemplateDraftService.new(draft, @actor, draft.lock_version).perform
  rescue StandardError => e
    Rails.logger.error("Calendar template submission failed (#{e.class}): #{e.message}")
    record_failure(draft, e)
  end

  def advance_revision_for_remote_retry(draft)
    latest = latest_submission(draft)
    return unless latest && RETRYABLE_REMOTE_STATUSES.include?(latest.remote_status) && latest.revision == draft.lock_version

    draft.update!(lock_version: draft.lock_version + 1)
  end

  def record_failure(draft, error)
    submission = draft.submissions.find_or_initialize_by(revision: draft.lock_version)
    details = { 'code' => error_code(error), 'error_class' => error.class.name }
    attributes = { status: 'failed', error_details: details }
    if submission.new_record?
      attributes.merge!(account: @account, actor: @actor, waba_id: draft.waba_id, name: draft.name, language: draft.language,
                        snapshot: { 'submission_error' => true }, payload_digest: Digest::SHA256.hexdigest(error.class.name))
    end
    submission.assign_attributes(attributes)
    submission.save!
    Whatsapp::TemplateBackgroundTask.publish(submission)
    submission
  end

  def error_code(error)
    return 'draft_changed' if error.is_a?(ActiveRecord::StaleObjectError)
    return error.code if error.is_a?(Whatsapp::TemplateComponentsBuilder::Invalid)

    'submission_failed'
  end

  def result_for(target, reason)
    { function: target.fetch(:function), waba_id: target.fetch(:waba_id), reason: reason }
  end
end
