module Integrations::GoogleTranslate::CredentialsValidator
  KEY_FIELDS = %w[client_email private_key].freeze

  def self.valid?(hook)
    credentials = hook.google_translate_credentials
    return false unless credentials.is_a?(Hash) && KEY_FIELDS.all? { |field| credentials[field].present? }

    Integrations::GoogleTranslate::ProcessorService.new(hook: hook).detect('Hello')
    true
  rescue JSON::ParserError, Google::Cloud::Error, Signet::AuthorizationError, OpenSSL::PKey::PKeyError => e
    Rails.logger.warn("[google-translate-validator] #{e.class}: #{e.message}")
    false
  end
end
