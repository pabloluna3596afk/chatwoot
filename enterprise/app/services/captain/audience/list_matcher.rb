class Captain::Audience::ListMatcher
  def initialize(contact, conversation)
    @contact = contact
    @conversation = conversation
    @phone_normalizer = Captain::Audience::PhoneNormalizer.new(conversation.account, conversation.inbox)
  end

  def missing?(type)
    values(type).empty?
  end

  def matches?(type, entries)
    actual = values(type)
    entries.any? do |entry|
      case type
      when 'phones' then actual.include?(@phone_normalizer.normalize(entry))
      when 'emails' then actual.any? { |email| email_match?(email, entry.downcase) }
      when 'channel_ids' then actual.include?(entry)
      end
    end
  end

  private

  def values(type)
    case type
    when 'phones' then [@phone_normalizer.normalize(@contact.phone_number)].compact_blank
    when 'emails' then [@contact.email&.downcase].compact_blank
    when 'channel_ids' then channel_ids
    end
  end

  def channel_ids
    attributes = @contact.additional_attributes
    [@conversation.contact_inbox&.source_id, attributes['social_instagram_user_name'],
     attributes.dig('social_profiles', 'instagram')].compact_blank
  end

  def email_match?(email, entry)
    entry.start_with?('@') ? email.split('@', 2).last == entry.delete_prefix('@') : email == entry
  end
end
