class Whatsapp::TemplateStatusWebhookService
  FIELD = 'message_template_status_update'.freeze
  STATUSES = (%w[APPROVED PENDING] + Whatsapp::TemplateBackgroundTask::ERROR_STATUSES).freeze

  def self.handles?(params)
    params.dig(:entry, 0, :changes, 0, :field) == FIELD
  end

  def initialize(params)
    @params = params
  end

  def perform
    @params.fetch(:entry).each do |entry|
      entry.fetch(:changes).each do |change|
        process(entry.fetch(:id), change.fetch(:value)) if change[:field] == FIELD
      end
    end
  end

  private

  def process(waba_id, value)
    submissions = WhatsappTemplateSubmission.where(waba_id: waba_id, remote_id: value.fetch(:message_template_id).to_s)
    submissions.includes(:account, :whatsapp_template_draft).find_each do |submission|
      submission.with_lock do
        previous_status = submission.remote_status
        attributes = { remote_status: value.fetch(:event), remote_reason: value[:reason] }
        attributes[:remote_category] = value[:message_template_category] if value.key?(:message_template_category)
        attributes[:remote_category] = value[:category] if value.key?(:category)
        submission.update!(attributes)
        next if previous_status == submission.remote_status

        Whatsapp::TemplateBackgroundTask.publish(submission) if STATUSES.include?(submission.remote_status)
        Whatsapp::SyncTemplateWabaJob.perform_later(submission.account_id, submission.waba_id)
      end
    end
  end
end
