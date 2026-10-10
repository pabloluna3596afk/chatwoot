class Whatsapp::CampaignConversationAttributor
  pattr_initialize [:conversation!, :inbox!, :message_payload!, :outgoing_echo]

  def perform
    return unless attributable?

    context_id = message_payload[:context]&.dig(:id) || message_payload[:context]&.[]('id')
    return if context_id.blank?

    # ponytail: only Meta reply context (buttons / quoted reply); no heuristic for free-text replies
    recipient = CampaignRecipient.find_by(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: context_id
    )
    return unless recipient

    conversation.update!(campaign_id: recipient.campaign_id)
    record_campaign_message(recipient)
  end

  private

  def attributable?
    !outgoing_echo && inbox.account.feature_enabled?(:whatsapp_campaign) && conversation.campaign_id.blank?
  end

  # A campaign opens no conversation when it is sent, so the template has no message in the chat. When the customer answers,
  # the conversation exists: show what they were sent, dated when it was sent so it reads before their reply. The message
  # carries the WhatsApp id it was sent with, so it is never sent again, and it must never block the customer's message.
  def record_campaign_message(recipient)
    campaign = recipient.campaign
    return if campaign.template_params.blank?
    return if conversation.messages.exists?(source_id: recipient.source_id)

    template_params = rendered_template_params(campaign)
    return if template_params.blank?

    last_activity_at = conversation.last_activity_at
    campaign_message = create_campaign_message(campaign, recipient, template_params)
    link_reply_to(campaign_message)
    # The message is older than the reply: it must not pull the conversation back in the list.
    conversation.update_columns(last_activity_at: last_activity_at) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error "Whatsapp campaign message not recorded for conversation #{conversation.id}: #{e.message}"
  end

  # The reply was saved before this message existed, so it only knows the WhatsApp id it answered: point it at the message.
  def link_reply_to(campaign_message)
    reply = conversation.messages.find_by(source_id: message_payload[:id])
    return if reply.blank? || reply.content_attributes['in_reply_to'].present?

    reply.update!(content_attributes: reply.content_attributes.merge('in_reply_to' => campaign_message.id))
  end

  def rendered_template_params(campaign)
    Whatsapp::LiquidTemplateProcessorService.new(campaign: campaign, contact: conversation.contact)
                                            .process_template_params(campaign.template_params)
  end

  def create_campaign_message(campaign, recipient, template_params)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      status: :delivered,
      sender: campaign.sender,
      content: recipient.message_content.presence || campaign.message.presence || campaign.title,
      source_id: recipient.source_id,
      created_at: recipient.sent_at || Time.current,
      additional_attributes: { campaign_id: campaign.id, template_params: template_params },
      content_attributes: { external_echo: true }
    )
  end
end
