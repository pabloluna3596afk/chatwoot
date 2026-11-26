class Calendar::TemplateDrafts::Submitter
  def initialize(account:, actor:, functions:, waba_ids:)
    @account = account
    @actor = actor
    @functions = functions
    @waba_ids = waba_ids
  end

  def perform
    submissions = []
    @functions.each do |function|
      source = source_draft(function)
      @waba_ids.each do |waba_id|
        draft = destination_draft(source, waba_id)
        latest = draft.submissions.where(waba_id: waba_id, language: draft.language).order(revision: :desc).first
        next if already_sent?(latest)

        submissions << submit(draft)
      end
    end
    submissions
  end

  private

  def source_draft(function)
    saved = (@account.calendar_template_preparation || {}).dig('results', function)
    draft = @account.whatsapp_template_drafts.active.find_by(id: saved&.fetch('draft_id', nil))
    raise ActiveRecord::RecordNotFound unless draft

    draft
  end

  def destination_draft(source, waba_id)
    return source if source.waba_id == waba_id

    @account.whatsapp_template_drafts.active.find_by(name: source.name, language: source.language, waba_id: waba_id) ||
      source.dup.tap do |draft|
        draft.assign_attributes(account: @account, waba_id: waba_id, preferred_channel: destination_channel(waba_id),
                                created_by: @actor, updated_by: @actor, source_draft: source, lock_version: 0)
        draft.media.attach(source.media.blob) if source.media.attached?
        draft.save!
      end
  end

  def destination_channel(waba_id)
    @account.whatsapp_channels.where(provider: 'whatsapp_cloud').detect do |channel|
      channel.provider_config['business_account_id'] == waba_id
    end || raise(ActiveRecord::RecordNotFound)
  end

  def already_sent?(submission)
    return false unless submission

    submission.status.in?(%w[submitting reconciling submitted]) || submission.remote_status.present?
  end

  def submit(draft)
    Whatsapp::SubmitTemplateDraftService.new(draft, @actor, draft.lock_version).perform
  rescue StandardError => error
    submission = draft.submissions.find_or_initialize_by(revision: draft.lock_version)
    attributes = { status: 'failed', error_details: { 'code' => 'submission_failed', 'detail' => error.message } }
    if submission.new_record?
      attributes.merge!(account: @account, actor: @actor, waba_id: draft.waba_id, name: draft.name, language: draft.language,
                        snapshot: { 'submission_error' => true }, payload_digest: Digest::SHA256.hexdigest(error.class.name))
    end
    submission.assign_attributes(attributes)
    submission.save!
    Whatsapp::TemplateBackgroundTask.publish(submission)
    submission
  end
end
