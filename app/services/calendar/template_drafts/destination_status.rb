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
    destination_payload(template).merge('waba_id' => waba_id, 'channels' => channel_payload)
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

  def destination_payload(template)
    state, reason = template ? ['usable', nil] : unavailable
    { 'state' => state, 'reason' => reason, 'resource_id' => @resource&.id,
      'draft_id' => destination_draft&.id || draft&.id, 'via' => template ? resolved_via : 'none',
      'submission' => submission_payload }
  end

  def channel_payload
    @channels.map { |channel| { 'id' => channel.id, 'name' => channel.inbox.name, 'phone_number' => channel.phone_number } }
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
    return resource_state if @resource&.status_incompatible?
    return remote_state unless draft

    submission_state_or_draft
  end

  def resource_state
    ['incompatible', @resource.incompatibility_reason]
  end

  def submission_state_or_draft
    submission = latest_submission
    return submission_state(submission) if submission

    %w[not_submitted draft_not_submitted]
  end

  def latest_submission
    destination_draft&.submissions&.where(waba_id: waba_id, language: @language)&.order(revision: :desc)&.first
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
    return %w[incompatible explicit_link_required] if submission.remote_status == 'APPROVED'
    return ['incompatible', submission.remote_status.downcase] if terminal_remote_status?(submission)
    return %w[not_submitted submission_failed] if failed_submission?(submission)

    %w[pending_approval awaiting_approval]
  end

  def terminal_remote_status?(submission)
    %w[REJECTED PAUSED DISABLED].include?(submission.remote_status)
  end

  def failed_submission?(submission)
    submission.status == 'failed'
  end

  def submission_payload
    submission = destination_draft&.submissions&.where(waba_id: waba_id, language: @language)&.order(revision: :desc)&.first
    return unless submission

    submission.attributes.slice('id', 'revision', 'status', 'remote_status', 'remote_reason')
              .merge('error_details' => safe_error_details(submission),
                     'revision_current' => submission.revision == destination_draft.lock_version)
  end

  def safe_error_details(submission)
    { 'code' => submission.error_details['code'] }.compact
  end

  def destination_draft
    @destination_draft ||= @account.whatsapp_template_drafts.active.find_by(
      name: Calendar::TemplateDefinitions::FUNCTIONS.fetch(@function), language: @language, waba_id: waba_id
    ) || draft
  end
end
