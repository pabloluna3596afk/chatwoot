require 'rails_helper'

RSpec.describe Captain::Audience::PhoneNormalizer do
  let(:account) { build(:account, settings: { 'country_code' => 'EC' }) }
  let(:inbox) { build(:inbox, account: account) }
  let(:normalizer) { described_class.new(account, inbox) }

  ['0991234567', '0991 234-567', '+593 991-234-567', '+593991234567'].each do |number|
    it "normalizes #{number} to E.164 using the account country" do
      expect(normalizer.normalize(number)).to eq('+593991234567')
    end
  end

  it 'uses the WhatsApp number country when the account has no country' do
    account.settings = {}
    whatsapp = build(:channel_whatsapp, account: account, phone_number: '+593987654321')
    inbox.channel = whatsapp

    expect(normalizer.normalize('0991234567')).to eq('+593991234567')
  end

  it 'gives the account country precedence over the WhatsApp number country' do
    inbox.channel = build(:channel_whatsapp, account: account, phone_number: '+14155552671')

    expect(normalizer.normalize('0991234567')).to eq('+593991234567')
  end

  it 'compares local numbers literally when no country can be deduced' do
    account.settings = {}

    expect(normalizer.normalize('0991 234-567')).to eq('0991 234-567')
  end

  it 'still normalizes international numbers when no country can be deduced' do
    account.settings = {}

    expect(normalizer.normalize('+593 991-234-567')).to eq('+593991234567')
  end

  it 'preserves an invalid number when the WhatsApp country cannot be deduced' do
    account.settings = {}
    inbox.channel = build(:channel_whatsapp, account: account, phone_number: 'invalid')

    expect(normalizer.normalize('0991234567')).to eq('0991234567')
  end
end
