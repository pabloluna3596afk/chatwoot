class Whatsapp::TemplateBackgroundTask
  ERROR_STATUSES = %w[REJECTED DISABLED PAUSED FLAGGED].freeze
  FINAL_STATUSES = %w[APPROVED REJECTED].freeze
  REMOTE_STATES = { 'APPROVED' => %w[success approved], 'REJECTED' => %w[error rejected], 'DISABLED' => %w[error rejected],
                    'PAUSED' => %w[error rejected], 'FLAGGED' => %w[error rejected] }.freeze

  def self.publish(submission)
    status, key = state_for(submission)
    account = submission.account
    detail = I18n.t("background_tasks.whatsapp_template.#{key}", locale: account.locale)
    reason = submission.remote_reason.presence || submission.error_details.values_at('error_user_msg', 'detail').find(&:present?)
    detail = "#{detail}: #{reason}" if status == 'error' && reason.present?
    BackgroundTasks::Notifier.publish(
      account: account, id: "whatsapp_template_submission:#{submission.id}", kind: 'whatsapp_template', title: submission.name,
      status: status, detail: detail,
      link: { label: I18n.t('background_tasks.whatsapp_template.link', locale: account.locale),
              route: { name: 'settings_templates', params: { accountId: account.id }, query: { q: submission.name } } }
    )
  end

  def self.state_for(submission)
    return %w[error failed] if submission.status == 'failed'

    REMOTE_STATES.fetch(submission.remote_status) do
      ['running', submission.status == 'submitted' ? 'review' : 'sending']
    end
  end
  private_class_method :state_for
end
