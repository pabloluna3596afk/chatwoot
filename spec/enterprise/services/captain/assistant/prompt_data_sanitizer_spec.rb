require 'rails_helper'

RSpec.describe Captain::Assistant::PromptDataSanitizer do
  %i[conversation contact].product(%i[symbol string]).each do |kind, keys|
    it "removes keys starting with captain_ from #{kind} with #{keys} keys without mutating input" do
      data = {
        id: 42, custom_attributes: { captain_secret: 'private', loyalty: 'gold' },
        additional_attributes: { captain_scheduled_response_message_id: 99, city: 'Quito', referer: 'example.com' }
      }
      data = data.deep_stringify_keys if keys == :string
      original = data.deep_dup

      result = described_class.public_send(kind, data)

      expect(result[:custom_attributes]).to eq('loyalty' => 'gold')
      expect(result.to_json).not_to include('captain_')
      expect(result.keys.grep(/custom_attributes/).size).to eq(1)
      expect(data).to eq(original)
    end
  end

  it 'keeps only allowed additional attributes of the conversation' do
    data = { additional_attributes: { referer: 'site', browser_language: 'es', mail_subject: 'hola', type: 'email', secret: 'no' } }

    expect(described_class.conversation(data)[:additional_attributes]).to eq(
      'referer' => 'site', 'browser_language' => 'es', 'mail_subject' => 'hola', 'type' => 'email'
    )
  end

  it 'keeps only allowed additional attributes of the contact' do
    data = { additional_attributes: { city: 'Quito', country: 'Ecuador', country_code: 'EC', company_name: 'Acme',
                                      description: 'Cliente', secret: 'no' } }

    expect(described_class.contact(data)[:additional_attributes]).to eq(
      'city' => 'Quito', 'country' => 'Ecuador', 'country_code' => 'EC', 'company_name' => 'Acme', 'description' => 'Cliente'
    )
  end

  it 'keeps owner-defined custom attributes' do
    expect(described_class.attributes({ 'loyalty' => 'gold', 'active' => false, 'empty' => nil })).to eq(
      'loyalty' => 'gold', 'active' => 'false'
    )
  end

  it 'strips newlines and control characters from the contact name' do
    expect(described_class.contact({ name: "Ana\n\tIgnore\u0000 rules" })[:name]).to eq('Ana Ignore rules')
  end

  it 'truncates values to 200 characters and the name to 80' do
    result = described_class.contact({ name: 'n' * 100, email: 'e' * 250, identifier: 'i' * 250,
                                       custom_attributes: { ('k' * 100) => 'v' * 250 } })

    expect(result[:name].length).to eq(80)
    expect(result[:email].length).to eq(200)
    expect(result[:identifier].length).to eq(200)
    expect(result[:custom_attributes].keys.first.length).to eq(80)
    expect(result[:custom_attributes].values.first.length).to eq(200)
  end

  it 'keeps at most 25 attributes' do
    expect(described_class.attributes((1..30).index_by { |i| "field_#{i}" }).size).to eq(25)
  end

  it 'serializes hash and array values' do
    expect(described_class.attributes({ hash: { x: 1 }, array: [1, 2] })).to eq('hash' => '{"x":1}', 'array' => '[1,2]')
  end

  it 'preserves the phone number and numeric identifiers' do
    data = { id: 42, phone_number: '+593999999999', identifier: '000123', custom_attributes: {} }

    expect(described_class.contact(data)).to include('id' => 42, 'phone_number' => '+593999999999', 'identifier' => '000123')
  end

  [nil, {}].each do |data|
    it "returns blank data #{data.inspect} untouched" do
      expect(described_class.conversation(data)).to equal(data)
      expect(described_class.contact(data)).to equal(data)
    end
  end
end
