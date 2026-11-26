class Whatsapp::RefreshTemplateSubmissionsJob < ApplicationJob
  queue_as :scheduled_jobs
  LIMIT = 100

  def perform
    final_statuses = Whatsapp::TemplateBackgroundTask::FINAL_STATUSES
    submissions = WhatsappTemplateSubmission.where(status: 'submitted')
                                            .where('remote_status IS NULL OR remote_status NOT IN (?)', final_statuses)
                                            .where(updated_at: ...10.minutes.ago).order(:updated_at, :id).limit(LIMIT)
                                            .includes(:actor, :whatsapp_template_draft, account: :whatsapp_channels)
    submissions.each do |submission|
      Whatsapp::TemplateSubmissionService.new(submission).perform(refresh: true)
      # Rotate checked rows even when Meta still reports the same state, so later batches cannot starve.
      submission.update!(updated_at: Time.current)
    end
  end
end
