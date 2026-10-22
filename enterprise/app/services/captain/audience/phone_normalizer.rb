class Captain::Audience::PhoneNormalizer
  def initialize(account, inbox)
    @account = account
    @inbox = inbox
  end

  def normalize(value)
    return value if value.blank?
    return value if country.blank? && !value.start_with?('+')

    parsed = TelephoneNumber.parse(value, country)
    parsed.valid? ? parsed.e164_number : value
  end

  private

  def country
    @country ||= @account.settings['country_code'].presence || whatsapp_country
  end

  def whatsapp_country
    return unless @inbox.channel_type == 'Channel::Whatsapp'

    parsed = TelephoneNumber.parse(@inbox.channel.phone_number)
    parsed.country.country_id if parsed.valid?
  end
end
