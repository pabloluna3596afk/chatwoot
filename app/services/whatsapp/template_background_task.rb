class Whatsapp::TemplateBackgroundTask
  ERROR_STATUSES = %w[REJECTED DISABLED PAUSED FLAGGED].freeze
  FINAL_STATUSES = %w[APPROVED REJECTED DISABLED PAUSED FLAGGED].freeze
  REMOTE_STATES = { 'APPROVED' => %w[success approved], 'REJECTED' => %w[error rejected], 'DISABLED' => %w[error rejected],
                    'PAUSED' => %w[error rejected], 'FLAGGED' => %w[error rejected] }.freeze

  def self.publish(submission)
    BackgroundTasks::Notifier.publish(account: submission.account, **task_payload(submission).except(:updated_at, :version).compact)
  end

  # Draft creator/updater and submission actor are audit attribution. Since live events go
  # to all account agents, this recovery source uses the same account-wide visibility.
  def self.tasks(account, _user)
    scope = WhatsappTemplateSubmission.where(account: account)
    active = scope.where(status: %w[submitting reconciling submitted])
                  .where('remote_status IS NULL OR remote_status NOT IN (?)', FINAL_STATUSES)
    recent = scope.where('updated_at >= ?', 24.hours.ago)
                  .where("status = 'failed' OR remote_status IN (?)", FINAL_STATUSES)
    (active.order(updated_at: :desc, id: :desc).includes(:account).to_a +
      recent.order(updated_at: :desc, id: :desc).limit(BackgroundTasks::Sources::LIMIT).includes(:account).to_a)
      .uniq(&:id).map { |submission| task_payload(submission) }
  end

  def self.task_payload(submission)
    status, key = state_for(submission)
    account = submission.account
    detail = I18n.t("background_tasks.whatsapp_template.#{key}", locale: account.locale)
    reason = submission.remote_reason.presence || submission.error_details.values_at('error_user_msg', 'detail').find(&:present?)
    detail = "#{detail}: #{reason}" if status == 'error' && reason.present?
    {
      id: "whatsapp_template_submission:#{submission.id}", kind: 'whatsapp_template', title: submission.name,
      status: status, phase: phase_for(status, submission),
      updated_at: submission.updated_at.iso8601, version: submission.updated_at.to_f, detail: detail,
      link: { label: I18n.t('background_tasks.whatsapp_template.link', locale: account.locale),
              route: { name: 'settings_templates', params: { accountId: account.id }, query: { q: submission.name } } }
    }
  end

  def self.phase_for(status, submission)
    return unless status == 'running'

    submission.status == 'submitted' ? 'waiting' : 'running'
  end

  def self.state_for(submission)
    return %w[error failed] if submission.status == 'failed'

    REMOTE_STATES.fetch(submission.remote_status) do
      ['running', submission.status == 'submitted' ? 'review' : 'sending']
    end
  end
  private_class_method :state_for
end
