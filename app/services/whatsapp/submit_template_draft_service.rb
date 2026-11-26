class Whatsapp::SubmitTemplateDraftService
  def initialize(draft, actor, revision)
    @draft = draft
    @actor = actor
    @revision = revision
  end

  def perform
    submission, enqueue = @draft.with_lock do
      raise ActiveRecord::StaleObjectError.new(@draft, 'submit') unless @draft.lock_version == @revision

      submission = @draft.submissions.find_by(revision: @revision)
      retried_submission = retry_failed_submission(submission)
      next [retried_submission, true] if retried_submission
      next [submission, false] if submission

      [create_submission, true]
    end
    Whatsapp::SubmitTemplateDraftJob.perform_later(submission.id) if enqueue
    submission
  end

  private

  def retry_failed_submission(submission)
    return unless submission&.status == 'failed' && submission.remote_id.blank? && submission.remote_status.blank?

    submission.update!(status: 'submitting', error_details: {})
    Whatsapp::TemplateBackgroundTask.publish(submission)
    submission
  end

  def create_submission
    snapshot = Whatsapp::TemplateDraftValidator.new(@draft).snapshot!
    submission = @draft.submissions.create!(account: @draft.account, actor: @actor, revision: @revision, waba_id: @draft.waba_id,
                                            name: @draft.name, language: snapshot.fetch('payload').fetch('language'), snapshot: snapshot,
                                            payload_digest: Digest::SHA256.hexdigest(snapshot.to_json))
    submission.media.attach(@draft.media.blob) if @draft.media.attached?
    Whatsapp::TemplateBackgroundTask.publish(submission)
    submission
  end
end
