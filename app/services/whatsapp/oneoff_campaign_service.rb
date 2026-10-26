class Whatsapp::OneoffCampaignService
  pattr_initialize [:campaign!]

  BATCH_SIZE = 100

  def perform
    validate_campaign!
    Campaigns::SendWhatsappBatchJob.perform_later(campaign)
  end

  def perform_batch(cursor)
    contacts = audience_contacts.where('contacts.id > ?', cursor).order(:id).limit(BATCH_SIZE).to_a
    process_contacts(contacts)
    contacts.last.id if contacts.size == BATCH_SIZE
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign_type!
    raise "Invalid campaign #{campaign.id}" unless whatsapp_campaign? && campaign.one_off?
  end

  def whatsapp_campaign?
    campaign.inbox.inbox_type == 'Whatsapp'
  end

  def validate_campaign_status!
    raise 'Completed Campaign' if campaign.completed?
  end

  def validate_provider!
    raise 'WhatsApp Cloud provider required' unless whatsapp_cloud_channel?
  end

  def validate_feature_flag!
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def validate_campaign!
    validate_campaign_type!
    validate_campaign_status!
    validate_provider!
    validate_feature_flag!
  end

  def extract_audience_labels
    audience_label_ids = campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
    campaign.account.labels.where(id: audience_label_ids).pluck(:title)
  end

  def process_contact(contact)
    Rails.logger.info "Processing contact: #{contact.name} (#{contact.phone_number})"
    recipient = recipient_for(contact)
    unless recipient.previously_new_record?
      recipient.update!(error_message: 'Send outcome unknown after interruption; review before retrying') if recipient.queued?
      return
    end

    process_recipient(recipient)
  rescue StandardError => e
    Rails.logger.error "Failed to process WhatsApp campaign recipient contact_id=#{contact.id}: #{e.message}"
    recipient&.mark_failed!(message: e.message) if recipient&.queued?
  end

  def process_recipient(recipient)
    contact = recipient.contact
    destination, destination_error = campaign_destination(contact)
    return recipient.mark_skipped!(destination_error) if destination.blank?
    return recipient.mark_skipped!('no template_params') if campaign.template_params.blank?

    processed_template_params = process_liquid_template_params(contact)
    return recipient.mark_skipped!(@template_resolution_error) if processed_template_params.nil?

    send_whatsapp_template_message(recipient: recipient, to: destination, template_params: processed_template_params)
  end

  def audience_contacts
    campaign.account.contacts.tagged_with(extract_audience_labels, any: true)
  end

  def process_contacts(contacts)
    contacts.each { |contact| process_contact(contact) }
  end

  def recipient_for(contact)
    campaign.campaign_recipients.find_or_create_by!(contact: contact) do |recipient|
      recipient.account = campaign.account
      recipient.inbox = campaign.inbox
      recipient.phone_number = contact.phone_number
      recipient.send_attempted_at = Time.current
    end
  end

  def process_liquid_template_params(contact)
    liquid_processor = Whatsapp::LiquidTemplateProcessorService.new(campaign: campaign, contact: contact)
    processed_template_params = liquid_processor.process_template_params(campaign.template_params)
    @template_resolution_error = liquid_processor.resolution_error
    processed_template_params
  end

  def send_whatsapp_template_message(recipient:, to:, template_params:)
    if (blocked_reason = authentication_template_block_reason(to, template_params))
      recipient.mark_skipped!(blocked_reason)
      return
    end

    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params
    )

    template_info = processor.call
    return recipient.mark_skipped!('invalid template') if template_info.first.blank?

    send_template_to_provider(recipient, to, template_info)
  rescue StandardError => e
    Rails.logger.error "Failed to send WhatsApp template message to #{to}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
    recipient.mark_failed!(message: e.message)
    nil
  end

  def send_template_to_provider(recipient, to, template_info)
    name, namespace, lang_code, processed_parameters = template_info
    wamid = channel.send_template(to, {
                                    name: name,
                                    namespace: namespace,
                                    lang_code: lang_code,
                                    parameters: processed_parameters
                                  }, nil)
    wamid.present? ? recipient.mark_sent!(wamid) : recipient.mark_failed!(message: 'WhatsApp API returned no message id')
  end

  def authentication_template_block_reason(destination, params)
    error = Whatsapp::AuthenticationTemplateGuard.new(channel: channel, recipient: destination, template_params: params).error
    return unless error

    Rails.logger.warn "Skipping BSUID campaign recipient: #{error}"
    error
  end

  # Phone number first; contacts known only by a WhatsApp BSUID are reached through that identity.
  def campaign_destination(contact)
    return [contact.phone_number, nil] if contact.phone_number.present?

    bsuid_contact_inboxes = bsuid_contact_inboxes_for(contact)
    return [nil, 'no phone number'] if bsuid_contact_inboxes.empty?

    bsuid_recipient = preferred_bsuid_recipient(bsuid_contact_inboxes)
    return [bsuid_recipient, nil] if bsuid_recipient.present?

    [nil, 'multiple WhatsApp identities found']
  end

  def bsuid_contact_inboxes_for(contact)
    contact.contact_inboxes.where(inbox_id: inbox.id).select do |contact_inbox|
      bsuid_source_id?(contact_inbox.source_id)
    end
  end

  def preferred_bsuid_recipient(contact_inboxes)
    return contact_inboxes.first.source_id if contact_inboxes.one?
  end

  def bsuid_source_id?(source_id)
    source_id.to_s.delete_prefix('whatsapp:').match?(RegexHelper::WHATSAPP_BSUID_REGEX)
  end

  def whatsapp_cloud_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end
end

Whatsapp::OneoffCampaignService.prepend_mod_with('Whatsapp::OneoffCampaignService')
