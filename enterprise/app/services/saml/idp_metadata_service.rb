require 'ipaddr'
require 'net/http'

class Saml::IdpMetadataService
  class Error < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(reason.to_s)
    end
  end

  MAX_METADATA_BYTES = 1.megabyte
  TIMEOUT = 5

  def initialize(metadata_url)
    @metadata_url = metadata_url
  end

  def perform
    metadata = parse_metadata(fetch_metadata)
    certificates = Array(metadata[:idp_cert_multi]&.dig(:signing))

    {
      sso_url: metadata[:idp_sso_service_url],
      idp_entity_id: metadata[:idp_entity_id],
      signing_certificates: certificates.map { |certificate| OneLogin::RubySaml::Utils.format_cert(certificate) }
    }
  end

  private

  def fetch_metadata
    # Pin one public address, bypass ambient proxies, and never follow redirects to private hosts or HTTP.
    uri = metadata_uri
    Net::HTTP.start(uri.host, uri.port, nil, **http_options(uri)) { |http| read_response(http, uri) }
  rescue URI::InvalidURIError
    raise Error, :invalid_url
  rescue SocketError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout, Net::ProtocolError,
         SystemCallError, IOError => e
    Rails.logger.warn("SAML metadata fetch failed: #{e.class}")
    raise Error, :unreachable
  end

  def metadata_uri
    uri = URI.parse(@metadata_url)
    raise Error, :invalid_url unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?

    uri
  end

  def http_options(uri)
    addresses = SsrfFilter::DEFAULT_RESOLVER.call(uri.host)
    raise Error, :blocked_address if addresses.empty? || addresses.any? { |address| private_address?(address) }

    { use_ssl: true, ipaddr: addresses.first, open_timeout: TIMEOUT, read_timeout: TIMEOUT }
  end

  def read_response(http, uri)
    response_body = nil
    response = http.request(Net::HTTP::Get.new(uri.request_uri)) do |result|
      raise Error, :http_error unless result.is_a?(Net::HTTPSuccess)

      body = +''
      result.read_body do |chunk|
        body << chunk
        raise Error, :too_large if body.bytesize > MAX_METADATA_BYTES
      end
      response_body = body
    end
    raise Error, :http_error unless response.is_a?(Net::HTTPSuccess)

    response_body
  end

  def private_address?(address)
    ip = IPAddr.new(address)
    return private_address?(ip.native.to_s) if ip.ipv4_mapped?

    blocked_ranges = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
      192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
      203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10
      2001::/23 2001:db8::/32 ff00::/8
    ].map { |range| IPAddr.new(range) }
    blocked_ranges.any? { |range| range.family == ip.family && range.include?(ip) }
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    true
  end

  def parse_metadata(xml)
    document = xml.dup.force_encoding(Encoding::UTF_8)
    raise Error, :not_metadata if document.include?("\0") || !document.valid_encoding? || document.match?(/<!DOCTYPE|<!ENTITY/i)

    OneLogin::RubySaml::IdpMetadataParser.new.parse_to_hash(
      xml,
      sso_binding: [OneLogin::RubySaml::Utils::BINDINGS[:redirect]]
    )
  rescue REXML::ParseException, ArgumentError, OpenSSL::X509::CertificateError => e
    Rails.logger.warn("SAML metadata parse failed: #{e.class}")
    raise Error, :not_metadata
  end
end
