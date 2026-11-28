module Integrations::GoogleTranslate::CredentialsValidator
  KEY_ERRORS = [
    Integrations::GoogleTranslate::Client::InvalidCredentials,
    Google::Cloud::Error,
    Signet::AuthorizationError,
    OpenSSL::PKey::PKeyError,
    RuntimeError
  ].freeze

  def self.valid?(hook)
    Integrations::GoogleTranslate::ProcessorService.new(hook: hook).detect('Hello')
    true
  rescue JSON::ParserError, Google::Cloud::Error, Signet::AuthorizationError, OpenSSL::PKey::PKeyError => e
    Rails.logger.warn("[google-translate-validator] #{e.class}: #{e.message}")
    false
  end
end
