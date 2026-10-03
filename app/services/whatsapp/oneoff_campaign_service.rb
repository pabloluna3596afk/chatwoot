class Whatsapp::OneoffCampaignService
  pattr_initialize [:campaign!]

  def perform
    validate_campaign!
    process_audience(extract_audience_labels)
    campaign.refresh_execution_stats!
    campaign.completed!
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

  def build_recipient(contact)
    campaign.campaign_recipients.create!(
      account_id: campaign.account_id,
      inbox_id: campaign.inbox_id,
      contact_id: contact.id,
      phone_number: contact.phone_number,
      status: :queued
    )
  end

  def process_contact(contact)
    Rails.logger.info "Processing contact: #{contact.name} (#{contact.phone_number})"
    recipient = build_recipient(contact)

    destination, destination_error = campaign_destination(contact)
    if destination.blank?
      Rails.logger.warn "Skipping campaign recipient contact_id=#{contact.id}: #{destination_error}"
      recipient.mark_skipped!(destination_error)
      return
    end

    if campaign.template_params.blank?
      Rails.logger.error "Skipping contact #{contact.name} - no template_params found for WhatsApp campaign"
      recipient.mark_skipped!('no template_params')
      return
    end

    processed_template_params = process_liquid_template_params(contact)
    if processed_template_params.nil?
      recipient.mark_skipped!('liquid variables resolved to blank values')
      return
    end

    send_whatsapp_template_message(
      recipient: recipient,
      to: destination,
      template_params: processed_template_params
    )
  end

  def process_audience(audience_labels)
    contacts = campaign.account.contacts.tagged_with(audience_labels, any: true)
    Rails.logger.info "Processing #{contacts.count} contacts for campaign #{campaign.id}"

    contacts.each { |contact| process_contact(contact) }

    Rails.logger.info "Campaign #{campaign.id} processing completed"
  end

  def process_liquid_template_params(contact)
    liquid_processor = Whatsapp::LiquidTemplateProcessorService.new(campaign: campaign, contact: contact)
    processed_template_params = liquid_processor.process_template_params(campaign.template_params)

    Rails.logger.info "Skipping contact #{contact.name} - liquid variables resolved to blank values" if processed_template_params.nil?

    processed_template_params
  rescue StandardError => e
    Rails.logger.error "Failed to process liquid template params for contact #{contact.name}: #{e.message}"
    nil
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

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      recipient.mark_skipped!('invalid template')
      return
    end

    wamid = channel.send_template(to, {
                                   name: name,
                                   namespace: namespace,
                                   lang_code: lang_code,
                                   parameters: processed_parameters
                                 }, nil)

    if wamid.present?
      recipient.mark_sent!(wamid)
    else
      recipient.mark_failed!('WhatsApp API returned no message id')
    end
  rescue StandardError => e
    Rails.logger.error "Failed to send WhatsApp template message to #{to}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
    recipient.mark_failed!(e.message)
    nil
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
