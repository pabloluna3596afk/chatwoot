require 'google/cloud/translate/v3'

module Integrations::GoogleTranslate::CredentialsValidator
  KEY_FIELDS = %w[client_email private_key].freeze
  KEY_ERRORS = [Google::Cloud::Error, Signet::AuthorizationError, OpenSSL::PKey::PKeyError, RuntimeError].freeze

  def self.valid?(hook)
    credentials = hook.google_translate_credentials
    return false unless credentials.is_a?(Hash) && credentials['type'] == 'service_account' &&
                        KEY_FIELDS.all? { |field| credentials[field].is_a?(String) && credentials[field].present? }

    Integrations::GoogleTranslate::ProcessorService.new(hook: hook).detect('Hello')
    true
  rescue JSON::ParserError, *KEY_ERRORS => e
    Rails.logger.warn("[google-translate-validator] #{e.class}: #{e.message}")
    false
  end
end
