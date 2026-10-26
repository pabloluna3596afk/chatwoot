# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Saml::IdpMetadataService do
  let(:metadata_url) { 'https://idp.example.com/saml/metadata' }
  let(:certificate) { build(:account_saml_settings).certificate }
  let(:metadata_xml) do
    body = certificate.gsub(/-----(BEGIN|END) CERTIFICATE-----|\s/, '')
    <<~XML
      <md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" xmlns:ds="http://www.w3.org/2000/09/xmldsig#" entityID="https://idp.example.com/entity">
        <md:IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
          <md:KeyDescriptor use="signing"><ds:KeyInfo><ds:X509Data><ds:X509Certificate>#{body}</ds:X509Certificate></ds:X509Data></ds:KeyInfo></md:KeyDescriptor>
          <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://idp.example.com/sso"/>
        </md:IDPSSODescriptor>
      </md:EntityDescriptor>
    XML
  end

  before do
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).and_call_original
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).with('idp.example.com').and_return(['93.184.216.34'])
    stub_request(:get, metadata_url).to_return(status: 200, body: metadata_xml)
  end

  it 'extracts the IdP endpoint, entity ID, and signing certificate' do
    expect(described_class.new(metadata_url).perform).to eq(
      sso_url: 'https://idp.example.com/sso',
      idp_entity_id: 'https://idp.example.com/entity',
      signing_certificates: [certificate.strip]
    )
  end

  it 'rejects non-HTTPS URLs before making a request' do
    expect { described_class.new('http://idp.example.com/metadata').perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:invalid_url) }
    expect(a_request(:get, 'http://idp.example.com/metadata')).not_to have_been_made
  end

  it 'rejects malformed URLs before making a request' do
    expect { described_class.new('https://[invalid/metadata').perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:invalid_url) }
  end

  it 'blocks private DNS results' do
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).with('idp.example.com').and_return(['10.0.0.5'])
    expect { described_class.new(metadata_url).perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:blocked_address) }
  end

  it 'blocks IPv4 loopback addresses encoded as IPv6' do
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).with('idp.example.com').and_return(['::ffff:127.0.0.1'])
    expect { described_class.new(metadata_url).perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:blocked_address) }
  end

  it 'does not follow redirects' do
    stub_request(:get, metadata_url).to_return(status: 302, headers: { 'Location' => 'http://127.0.0.1/metadata' })
    expect { described_class.new(metadata_url).perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:http_error) }
    expect(a_request(:get, 'http://127.0.0.1/metadata')).not_to have_been_made
  end

  it 'rejects XML external entity declarations' do
    stub_request(:get, metadata_url).to_return(status: 200, body: '<!DOCTYPE foo [<!ENTITY x SYSTEM "file:///etc/passwd">]><foo>&x;</foo>')
    expect { described_class.new(metadata_url).perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:not_metadata) }
  end

  it 'rejects UTF-16 documents before parsing declarations' do
    xml = '<!DOCTYPE foo [<!ENTITY x SYSTEM "file:///etc/passwd">]><foo>&x;</foo>'.encode(Encoding::UTF_16LE)
    stub_request(:get, metadata_url).to_return(status: 200, body: xml)
    expect { described_class.new(metadata_url).perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:not_metadata) }
  end

  it 'rejects responses larger than the metadata limit' do
    stub_request(:get, metadata_url).to_return(status: 200, body: 'x' * (described_class::MAX_METADATA_BYTES + 1))
    expect { described_class.new(metadata_url).perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:too_large) }
  end

  it 'uses bounded connection and read timeouts' do
    expect(Net::HTTP).to receive(:start).with(
      'idp.example.com', 443, nil, hash_including(open_timeout: 5, read_timeout: 5)
    ).and_raise(Net::ReadTimeout)

    expect { described_class.new(metadata_url).perform }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:unreachable) }
  end
end
