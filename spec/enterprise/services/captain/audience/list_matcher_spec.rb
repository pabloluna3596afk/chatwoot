require 'rails_helper'

RSpec.describe Captain::Audience::ListMatcher do
  subject(:matcher) { described_class.new(contact, conversation) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, email: 'customer@example.com', phone_number: '+593991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  it 'matches exact email addresses, domains and normalized phone numbers' do
    expect(matcher.matches?('emails', ['CUSTOMER@EXAMPLE.COM'])).to be true
    expect(matcher.matches?('emails', ['@example.com'])).to be true
    expect(matcher.matches?('phones', ['+593 99 123 4567'])).to be true
  end

  it 'does not match malformed email and phone entries' do
    expect(matcher.matches?('emails', ['invalid-address'])).to be false
    expect(matcher.matches?('phones', ['invalid-phone'])).to be false
    expect(matcher.matches?('emails', ['@notexample.com'])).to be false
  end

  it 'uses only the supplied account contact and conversation identifiers' do
    other_contact = create(:contact, email: 'other@private.com')
    other_conversation = create(:conversation, contact: other_contact, account: other_contact.account)
    expect(matcher.matches?('emails', [other_contact.email])).to be false
    expect(matcher.matches?('channel_ids', [other_conversation.contact_inbox.source_id])).to be false
    expect(matcher.matches?('channel_ids', [conversation.contact_inbox.source_id])).to be true
  end

  it 'recognizes a missing email' do
    contact.update!(email: nil)
    expect(matcher.missing?('emails')).to be true
  end
end
