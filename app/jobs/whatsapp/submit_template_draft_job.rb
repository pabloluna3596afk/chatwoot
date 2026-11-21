class Whatsapp::SubmitTemplateDraftJob < ApplicationJob
  queue_as :default

  def perform(submission_id, refresh: false)
    submission = WhatsappTemplateSubmission.find(submission_id)
    Whatsapp::TemplateSubmissionService.new(submission).perform(refresh: refresh)
  end
end
