require 'rails_helper'

RSpec.describe Integrations::GoogleTranslate::CredentialsValidator do
  let(:hook) do
    build(:integrations_hook, :google_translate,
          access_token: { type: 'service_account', client_email: 'translator@example.com', private_key: 'private-key' }.to_json)
  end

  it 'makes a minimal language detection request to validate credentials' do
    processor = instance_double(Integrations::GoogleTranslate::ProcessorService, detect: 'en')
    expect(Integrations::GoogleTranslate::ProcessorService).to receive(:new).with(hook: hook).and_return(processor)

    expect(described_class.valid?(hook)).to be true
  end

  it 'rejects credentials missing service account key fields' do
    hook.access_token = { type: 'service_account', client_email: 'translator@example.com' }.to_json

    expect(Integrations::GoogleTranslate::ProcessorService).not_to receive(:new)
    expect(described_class.valid?(hook)).to be false
  end
end
