# Records an internal activity using the diagnosis already saved with the opening.
class Captain::EngagementActivity
  CHANNELS = {
    'Channel::Whatsapp' => 'whatsapp',
    'Channel::Instagram' => 'instagram',
    'Channel::FacebookPage' => 'messenger',
    'Channel::WebWidget' => 'web',
    'Channel::Email' => 'email',
    'Channel::Sms' => 'sms',
    'Channel::TwilioSms' => 'sms',
    'Channel::Api' => 'api',
    'Channel::Telegram' => 'telegram',
    'Channel::Line' => 'line',
    'Channel::TwitterProfile' => 'twitter',
    'Channel::Tiktok' => 'tiktok'
  }.freeze

  def initialize(conversation, assistant)
    @conversation = conversation
    @assistant = assistant
    @locale = conversation.account.locale
    @result = conversation.additional_attributes.fetch('captain_skip_reason').with_indifferent_access
  end

  def perform
    @conversation.messages.create!(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :activity,
      content: translated_content,
      additional_attributes: { captain_skip_reason: @result }
    )
  end

  private

  def translation_params
    condition = @result[:condition]
    params = { assistant: @assistant.name.presence || 'Captain', channel: channel_label }
    return params unless condition

    params.merge(
      attribute: attribute_label(condition[:attribute_key]),
      operator: I18n.t("captain.engagement.operators.#{condition[:filter_operator]}", locale: @locale),
      value: Array(condition[:values]).join(', ')
    )
  end

  def translated_content
    content = I18n.t(
      "captain.engagement.#{@result[:reason]}",
      **translation_params,
      locale: @locale
    )
    ERB::Util.html_escape(content)
  end

  def attribute_label(key)
    definition = @conversation.account.custom_attribute_definitions.contact_attribute.find_by(attribute_key: key)
    return definition.attribute_display_name if definition

    I18n.t("captain.engagement.attributes.#{key}", locale: @locale)
  end

  def channel_label
    inbox = @conversation.inbox
    key = CHANNELS.fetch(inbox.channel_type)
    key = 'whatsapp' if inbox.twilio? && inbox.channel.medium == 'whatsapp'
    if inbox.facebook? && @conversation.additional_attributes['type'] == 'instagram_direct_message'
      key = 'instagram'
    end
    I18n.t("captain.engagement.channels.#{key}", locale: @locale)
  end
end
