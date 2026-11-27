class Calendar::TemplateDrafts::DestinationStatus
  def initialize(account:, function:, language:, channels:)
    @account = account
    @function = function
    @language = language
    @channels = channels
    @channel = channels.first
  end

  def perform
    template = resolve_destination
    state, reason = template ? ['usable', nil] : unavailable
    { 'waba_id' => waba_id, 'channels' => @channels.map { |channel| { 'id' => channel.id, 'name' => channel.inbox.name } },
      'state' => state, 'reason' => reason, 'resource_id' => @resource&.id, 'draft_id' => draft&.id,
      'via' => template ? resolved_via : 'none' }
  end

  private

  def resolve_destination
    template = nil
    @channels.each do |channel|
      @channel = channel
      resolver = Calendar::TemplateResources.new(account: @account, function: @function, language: @language, channel: channel)
      template = resolver.resolve
      @resource = resolver.resource
      break unless template
    end
    template
  end

  def resolved_via
    @resource&.status_linked? ? 'linked' : 'legacy_by_name'
  end

  def waba_id
    @channel.provider_config['business_account_id'].presence
  end

  def draft
    return @draft if defined?(@draft)

    @draft = @resource&.whatsapp_template_draft || matching_draft
  end

  def matching_draft
    name = Calendar::TemplateDefinitions::FUNCTIONS.fetch(@function)
    @account.whatsapp_template_drafts.active.where(name: name, language: @language)
            .where(waba_id: [waba_id, nil]).order(waba_id: :asc, id: :asc).first
  end

  def unavailable
    return ['incompatible', @resource.incompatibility_reason] if @resource&.status_incompatible?
    return remote_state unless draft

    submission = draft.submissions.where(waba_id: waba_id, language: @language).order(revision: :desc).first
    return submission_state(submission) if submission

    %w[not_submitted draft_not_submitted]
  end

  def remote_state
    template = Array(@channel.message_templates).find do |item|
      item['name'] == Calendar::TemplateDefinitions::FUNCTIONS.fetch(@function) && item['language'] == @language
    end
    return %w[missing missing_template] unless template
    return %w[incompatible category] unless template['category'].to_s.casecmp?('UTILITY')
    return %w[pending_approval awaiting_approval] if template['status'].to_s.casecmp?('PENDING')

    %w[incompatible status]
  end

  def submission_state(submission)
    return approved_submission_state(submission) if submission.remote_status == 'APPROVED'
    return ['incompatible', submission.remote_status.downcase] if %w[REJECTED PAUSED DISABLED].include?(submission.remote_status)
    return %w[not_submitted submission_failed] if submission.status == 'failed'

    %w[pending_approval awaiting_approval]
  end

  def approved_submission_state(submission)
    template = Array(@channel.message_templates).find do |item|
      item['id'] == submission.remote_id && item['name'] == submission.name && item['language'] == submission.language
    end
    reason = Calendar::TemplateContract.new(function: @function, language: @language, template: template).incompatibility
    return ['incompatible', reason] if reason

    %w[usable nil]
  end
end
