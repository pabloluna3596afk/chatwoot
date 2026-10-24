class Conversations::ChannelType
  CHANNELS = {
    'Channel::Whatsapp' => 'whatsapp',
    'Channel::Instagram' => 'instagram',
    'Channel::FacebookPage' => 'messenger',
    'Channel::WebWidget' => 'web_widget',
    'Channel::Email' => 'email',
    'Channel::Sms' => 'sms',
    'Channel::TwilioSms' => 'sms',
    'Channel::Api' => 'api',
    'Channel::Telegram' => 'telegram',
    'Channel::Line' => 'line',
    'Channel::TwitterProfile' => 'twitter',
    'Channel::Tiktok' => 'tiktok'
  }.freeze

  AUTOMATION_VALUES = CHANNELS.except('Channel::TwitterProfile').values.uniq.freeze

  def self.for(conversation)
    inbox = conversation.inbox
    return 'whatsapp' if inbox.twilio? && inbox.channel.medium == 'whatsapp'
    return 'instagram' if inbox.facebook? && conversation.additional_attributes['type'] == 'instagram_direct_message'

    CHANNELS.fetch(inbox.channel_type, 'api')
  end
end
