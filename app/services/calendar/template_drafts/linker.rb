class Calendar::TemplateDrafts::Linker
  def initialize(account:, function:, channel_id:)
    @account = account
    @function = function
    @channel = account.whatsapp_channels.find_by(id: channel_id)
  end

  def perform(draft_id: nil, template_name: nil, remote_template_id: nil)
    validate_channel!
    draft = find_draft(draft_id) if draft_id
    selection = draft ? submitted_selection(draft) : [template_name, remote_template_id]
    resource = Calendar::TemplateResources.new(account: @account, function: @function,
                                               language: Calendar::TemplateDefinitions.language(@account), channel: @channel)
                                          .link!(template_name: selection.first, remote_template_id: selection.last, draft: draft)
    raise Whatsapp::TemplateComponentsBuilder::Invalid, resource.incompatibility_reason if resource.status_incompatible?

    Calendar::TemplateDrafts::Status.new(account: @account).perform
  end

  private

  def validate_channel!
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'invalid_channel' unless @channel
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'cloud_channel_required' unless @channel.provider == 'whatsapp_cloud'
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'missing_waba' if @channel.provider_config['business_account_id'].blank?
  end

  def find_draft(id)
    draft = @account.whatsapp_template_drafts.find_by(id: id)
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'invalid_draft' unless draft
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'destination_mismatch' unless draft.waba_id == @channel.provider_config['business_account_id']
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'language' unless draft.language == Calendar::TemplateDefinitions.language(@account)

    draft
  end

  def submitted_selection(draft)
    submission = draft.submissions.where(waba_id: draft.waba_id, language: draft.language).order(revision: :desc).first
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'missing_submission' if submission&.remote_id.blank?

    [submission.name, submission.remote_id]
  end
end
