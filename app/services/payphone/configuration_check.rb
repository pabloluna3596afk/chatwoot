require 'uri'

class Payphone::ConfigurationCheck
  KEYS = %w[
    ENABLE_PAYPHONE PAYPHONE_STORE_ID PAYPHONE_TOKEN PAYPHONE_BOX_TOKEN PAYPHONE_ENVIRONMENT PAYPHONE_RESPONSE_URL
    PAYPHONE_EXTERNAL_NOTIFICATION_ENABLED PAYPHONE_TAX_RATE PAYPHONE_CARD_COMMISSION_RATE
    PAYPHONE_COMMISSION_ENABLED PAYPHONE_GRACE_DAYS
  ].freeze

  Result = Struct.new(:valid?, :errors, keyword_init: true)

  def self.call(values:, frontend_url: ENV.fetch('FRONTEND_URL', nil))
    new(values: values, frontend_url: frontend_url).call
  end

  def initialize(values:, frontend_url:)
    @values = values
    @frontend_url = frontend_url
  end

  def call
    errors = []
    errors << I18n.t('super_admin.payphone.validation.store_id_required') if value('PAYPHONE_STORE_ID').blank?
    errors << I18n.t('super_admin.payphone.validation.token_required') if value('PAYPHONE_TOKEN').blank?
    errors << I18n.t('super_admin.payphone.validation.environment') unless %w[test production].include?(value('PAYPHONE_ENVIRONMENT'))
    validate_rate(errors, 'PAYPHONE_TAX_RATE', I18n.t('super_admin.payphone.rate_labels.tax'))
    validate_rate(errors, 'PAYPHONE_CARD_COMMISSION_RATE', I18n.t('super_admin.payphone.rate_labels.commission'))
    validate_grace_days(errors)
    validate_response_url(errors)

    Result.new(valid?: errors.empty?, errors: errors)
  end

  private

  def value(name)
    @values[name].to_s
  end

  def validate_rate(errors, key, label)
    rate = Float(value(key))
    errors << I18n.t('super_admin.payphone.validation.rate_range', label: label) unless rate.between?(0, 100)
  rescue ArgumentError, TypeError
    errors << I18n.t('super_admin.payphone.validation.rate_number', label: label)
  end

  def validate_grace_days(errors)
    days = Integer(value('PAYPHONE_GRACE_DAYS'))
    errors << I18n.t('super_admin.payphone.validation.grace_range') if days.negative?
  rescue ArgumentError, TypeError
    errors << I18n.t('super_admin.payphone.validation.grace_number')
  end

  def validate_response_url(errors)
    uri = URI.parse(value('PAYPHONE_RESPONSE_URL'))
    validate_response_uri(errors, uri)
  rescue URI::InvalidURIError
    errors << I18n.t('super_admin.payphone.validation.response_https')
  end

  def validate_response_uri(errors, uri)
    return errors << I18n.t('super_admin.payphone.validation.response_https') unless valid_response_uri?(uri)
    return errors << I18n.t('super_admin.payphone.validation.frontend_domain_required') if @frontend_url.blank?

    expected_host = frontend_host
    return errors << I18n.t('super_admin.payphone.validation.frontend_domain_required') if expected_host.blank?

    errors << I18n.t('super_admin.payphone.validation.response_domain') if uri.host != expected_host
    errors << I18n.t('super_admin.payphone.validation.response_path') unless uri.path == '/payphone/response' && uri.query.nil?
  end

  def valid_response_uri?(uri)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.fragment.nil?
  end

  def frontend_host
    URI.parse(@frontend_url).host
  rescue URI::InvalidURIError
    nil
  end
end
