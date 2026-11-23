class Calendar::TemplateDrafts::Status
  def initialize(account:)
    @account = account
  end

  def perform
    preparation = @account.calendar_template_preparation || {}
    results = preparation.fetch('results', {})
    language = preparation.fetch('language', Calendar::TemplateDefinitions.language(@account))
    language_status(preparation['language']).merge(
      'language' => language,
      'results' => Calendar::TemplateDefinitions::FUNCTIONS.keys.index_with { |function| result(function, results.fetch(function, {}), preparation) }
    )
  end

  private

  def effective_language
    Calendar::TemplateDefinitions.language(@account)
  end

  def language_status(prepared)
    { 'prepared_language' => prepared, 'effective_language' => effective_language,
      'language_changed' => prepared.present? && prepared != effective_language }
  end

  def destination_summary(function)
    targets = destinations(function)
    { 'destinations' => targets, 'ready_destinations' => targets.count { |target| target['state'] == 'usable' },
      'total_destinations' => targets.size }
  end

  def destinations(function)
    channels = @account.whatsapp_channels.where(provider: 'whatsapp_cloud').includes(:inbox).order(:id)
    channels.group_by { |channel| channel.provider_config['business_account_id'].presence }.filter_map do |waba, numbers|
      next unless waba

      Calendar::TemplateDrafts::DestinationStatus.new(account: @account, function: function, language: effective_language, channels: numbers).perform
    end
  end

  def result(function, saved, preparation)
    draft = @account.whatsapp_template_drafts.find_by(id: saved['draft_id'])
    targets = destination_summary(function)
    saved.reverse_merge('status' => 'pending', 'draft_id' => nil).merge(
      'draft_exists' => draft.present?, 'archived' => draft&.archived_at.present?
    ).merge(targets).merge(language_status(saved.fetch('prepared_language', preparation['language'])))
         .merge(resource_status(saved, draft)).merge(submission_status(draft))
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
