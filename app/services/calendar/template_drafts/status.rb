class Calendar::TemplateDrafts::Status
  def initialize(account:)
    @account = account
  end

  def perform
    preparation = @account.calendar_template_preparation || {}
    results = preparation.fetch('results', {})
    { 'language' => preparation.fetch('language', Calendar::TemplateDefinitions.language(@account)),
      'results' => Calendar::TemplateDefinitions::FUNCTIONS.keys.index_with { |function| result(results.fetch(function, {})) } }
  end

  private

  def result(saved)
    draft = @account.whatsapp_template_drafts.find_by(id: saved['draft_id'])
    saved.reverse_merge('status' => 'pending', 'draft_id' => nil).merge(
      'draft_exists' => draft.present?, 'archived' => draft&.archived_at.present?
    ).merge(resource_status(saved, draft)).merge(submission_status(draft))
  end

  def resource_status(saved, draft)
    resources = @account.calendar_template_resources.where(id: saved['resource_id'])
    resources = resources.or(@account.calendar_template_resources.where(whatsapp_template_draft_id: draft.id)) if draft
    rows = resources.order(:id).to_a
    { 'resource_id' => rows.find { |resource| resource.id == saved['resource_id'] }&.id,
      'linked' => rows.any?(&:status_linked?), 'resources' => rows.map { |resource| resource.attributes.slice('id', 'waba_id', 'status') } }
  end

  def submission_status(draft)
    submission = draft.submissions.order(revision: :desc).first if draft
    { 'submission_status' => submission&.status, 'remote_status' => submission&.remote_status,
      'submitted' => submission&.status == 'submitted', 'approved' => submission&.remote_status == 'APPROVED' }
  end
end
