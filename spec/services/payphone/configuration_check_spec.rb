require 'rails_helper'

RSpec.describe Payphone::ConfigurationCheck do
  let(:values) do
    {
      'PAYPHONE_STORE_ID' => 'store-123',
      'PAYPHONE_TOKEN' => 'test-token',
      'PAYPHONE_BOX_TOKEN' => 'public-test-token',
      'PAYPHONE_ENVIRONMENT' => 'test',
      'PAYPHONE_RESPONSE_URL' => 'https://inbox.example.test/payphone/response',
      'PAYPHONE_TAX_RATE' => '15',
      'PAYPHONE_CARD_COMMISSION_RATE' => '5.75',
      'PAYPHONE_GRACE_DAYS' => '3'
    }
  end

  it 'accepts complete values when the HTTPS response domain matches the frontend' do
    result = described_class.call(values: values, frontend_url: 'https://inbox.example.test')

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it 'accepts the Payphone token without a separate Cajita token' do
    values.delete('PAYPHONE_BOX_TOKEN')
    result = described_class.call(values: values, frontend_url: 'https://inbox.example.test')

    expect(result).to be_valid
  end

  it 'rejects a non-HTTPS response URL' do
    values['PAYPHONE_RESPONSE_URL'] = 'http://attacker.example/pay'
    result = described_class.call(values: values, frontend_url: 'https://inbox.example.test')

    expect(result).not_to be_valid
    expect(result.errors.join).to include('HTTPS')
  end

  it 'rejects a response URL from a different domain' do
    values['PAYPHONE_RESPONSE_URL'] = 'https://attacker.example/pay'
    result = described_class.call(values: values, frontend_url: 'https://inbox.example.test')

    expect(result).not_to be_valid
    expect(result.errors.join).to include('domain')
  end

  it 'rejects missing credentials and out-of-range settings' do
    values['PAYPHONE_TOKEN'] = ''
    values['PAYPHONE_BOX_TOKEN'] = ''
    values['PAYPHONE_TAX_RATE'] = '101'
    values['PAYPHONE_GRACE_DAYS'] = '-1'
    result = described_class.call(values: values)

    expect(result).not_to be_valid
    expect(result.errors.join).to include('token', 'VAT rate', 'Grace days')
  end
end
