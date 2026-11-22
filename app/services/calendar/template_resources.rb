# Account locking serializes preparation, including identities without a WABA. The
# unique indexes protect other writers; a uniqueness race is retried in a fresh transaction.
# Reads never create resources and never contact Meta. A selected, unusable version
# blocks legacy fallback; merely preparing an identity preserves installed legacy uses.
class Calendar::TemplateResources
  attr_reader :resource

  def initialize(account:, function:, language:, channel: nil)
    @account = account
    @function = function.to_s
    @language = language
    @channel = channel
    @legacy_name = Calendar::TemplateDefinitions::FUNCTIONS.fetch(@function)
  end

  def prepare!(template_name: @legacy_name, draft: nil)
    raise ArgumentError, 'Own WhatsApp Cloud channel required' if @channel && !cloud?

    write_resource do |record|
      next if record.persisted?

      record.assign_attributes(template_name: template_name, whatsapp_template_draft: draft)
      record.save!
    end
  end

  # An explicit local binding, never automatic adoption by name. Identity and content
  # are checked against the selected channel's synced mirror before the link is usable.
  def link!(template_name:, remote_template_id:, draft: nil)
    raise ArgumentError, 'WhatsApp Cloud WABA required' unless cloud? && waba_id.present?

    write_resource do |record|
      template = templates.find { |item| item['name'] == template_name && item['id'] == remote_template_id && item['language'] == @language }
      contract = Calendar::TemplateContract.new(function: @function, language: @language, template: template)
      reason = contract.incompatibility
      snapshot = reason ? {} : contract.snapshot.merge('draft_revision_at_link' => draft&.lock_version)
      record.update!(template_name: template_name, remote_template_id: remote_template_id, whatsapp_template_draft: draft,
                     status: reason ? 'incompatible' : 'linked', incompatibility_reason: reason,
                     linked_at: reason ? nil : Time.current, contract_snapshot: snapshot)
    end
  end

  def resolve
    return unless cloud?

    @resource = @account.calendar_template_resources.find_by(identity)
    return legacy_template if resource.nil? || resource.status_pending?
    return unless resource.status_linked?

    resource.with_lock do
      next unless resource.status_linked?

      verified_template
    end
  end

  def message_snapshot(template)
    contract = if resource&.status_linked?
                 resource.contract_snapshot
               else
                 definition = Calendar::TemplateDefinitions.definition(@function, @language)
                 labels = definition.fetch(:buttons)
                 { 'version' => Calendar::TemplateContract.version(template), 'variables' => Calendar::TemplateDefinitions::VARIABLES,
                   'actions' => labels.zip(Calendar::TemplateDefinitions::ACTIONS).to_h }
               end
    contract.merge('resource_id' => resource&.status_linked? ? resource.id : nil, 'function' => @function, 'language' => @language,
                   'waba_id' => waba_id, 'remote_template_id' => template['id'], 'template_name' => template['name'])
  end

  private

  def verified_template
    template = templates.find do |item|
      item['id'] == resource.remote_template_id && item['name'] == resource.template_name && item['language'] == @language
    end
    contract = Calendar::TemplateContract.new(function: @function, language: @language, template: template)
    reason = contract.incompatibility
    reason ||= 'version_changed' if contract.snapshot['version'] != resource.contract_snapshot['version']
    return template unless reason

    resource.update!(status: 'incompatible', incompatibility_reason: reason)
    nil
  end

  def identity
    { function: @function, language: @language, waba_id: waba_id }
  end

  def waba_id
    @channel&.provider_config&.fetch('business_account_id', nil).presence
  end

  def cloud?
    @channel.is_a?(Channel::Whatsapp) && @channel.account_id == @account.id && @channel.provider == 'whatsapp_cloud'
  end

  def templates
    Array(@channel.message_templates).select { |item| item.is_a?(Hash) }
  end

  def legacy_template
    templates.find do |item|
      item['name'] == @legacy_name && item['language'] == @language &&
        item['status'].to_s.casecmp?('APPROVED') && item['category'].to_s.casecmp?('UTILITY')
    end
  end

  def write_resource
    @account.with_lock(requires_new: true) do
      @resource = @account.calendar_template_resources.lock.find_or_initialize_by(identity)
      yield resource
      resource
    end
  rescue ActiveRecord::RecordNotUnique
    @account.with_lock(requires_new: true) do
      @resource = @account.calendar_template_resources.lock.find_by!(identity)
      yield resource
      resource
    end
  end
end
