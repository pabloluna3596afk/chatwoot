class Whatsapp::SubmitTemplateDraftService
  def initialize(draft, actor, revision)
    @draft = draft
    @actor = actor
    @revision = revision
  end

  def perform
    submission = @draft.with_lock do
      raise ActiveRecord::StaleObjectError.new(@draft, 'submit') unless @draft.lock_version == @revision

      @draft.submissions.find_by(revision: @revision) || create_submission
    end
    Whatsapp::SubmitTemplateDraftJob.perform_later(submission.id) if submission.status == 'submitting'
    submission
  end

  private

  def create_submission
    snapshot = Whatsapp::TemplateDraftValidator.new(@draft).snapshot!
    submission = @draft.submissions.create!(account: @draft.account, actor: @actor, revision: @revision, waba_id: @draft.waba_id,
                                            name: @draft.name, language: @draft.language, snapshot: snapshot,
                                            payload_digest: Digest::SHA256.hexdigest(snapshot.to_json))
    submission.media.attach(@draft.media.blob) if @draft.media.attached?
    submission
  end
end
