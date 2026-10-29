class SuperAdmin::AppConfigsController < SuperAdmin::ApplicationController
  GENERAL_CONFIGS = %w[ENABLE_ACCOUNT_SIGNUP FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS WEBHOOK_TIMEOUT MAXIMUM_FILE_UPLOAD_SIZE
                       WIDGET_TOKEN_EXPIRY].freeze
  META_INCIDENT_CONFIGS = %w[DISABLE_META_INBOX_CREATION DISABLE_META_MESSAGE_SENDING].freeze
  SHOPIFY_CONFIGS = %w[
    ENABLE_SHOPIFY_INTEGRATION
    SHOPIFY_CLIENT_ID
    SHOPIFY_CLIENT_SECRET
    SHOPIFY_APP_STORE_URL
    SHOPIFY_PARTNER_ORGANIZATION_ID
    SHOPIFY_PARTNER_APP_ID
    SHOPIFY_PARTNER_ACCESS_TOKEN
    SHOPIFY_PARTNER_API_VERSION
  ].freeze
  PAYPHONE_CONFIGS = Payphone::ConfigurationCheck::KEYS

  before_action :set_config
  before_action :allowed_configs
  def show
    load_config_values
  end

  def create
    errors = initial_config_errors
    errors.concat(save_app_configs) if errors.empty?

    return redirect_to super_admin_app_config_path(config: @config), alert: errors.join(', ') if errors.any?

    redirect_to super_admin_settings_path, flash: success_flash
  end

  def test
    submitted_values = params.fetch('app_config', {}).permit(*PAYPHONE_CONFIGS).to_h
    saved_values = InstallationConfig.where(name: PAYPHONE_CONFIGS).each_with_object({}) do |config, values|
      values[config.name] = config.value
    end
    result = Payphone::ConfigurationCheck.call(values: merged_payphone_values(saved_values, submitted_values))
    @test_result = result
    load_config_values
    render :show, status: result.valid? ? :ok : :unprocessable_entity
  end

  private

  def set_config
    @config = params[:config] || 'general'
  end

  def allowed_configs
    general_configs = GENERAL_CONFIGS + (ChatwootApp.chatwoot_cloud? ? META_INCIDENT_CONFIGS : [])

    mapping = {
      'facebook' => %w[FB_APP_ID FB_VERIFY_TOKEN FB_APP_SECRET IG_VERIFY_TOKEN FACEBOOK_API_VERSION ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT],
      'shopify' => SHOPIFY_CONFIGS,
      'microsoft' => %w[AZURE_APP_ID AZURE_APP_SECRET],
      'email' => %w[MAILER_INBOUND_EMAIL_DOMAIN ACCOUNT_EMAILS_LIMIT ACCOUNT_EMAILS_PLAN_LIMITS],
      'linear' => %w[LINEAR_CLIENT_ID LINEAR_CLIENT_SECRET],
      'slack' => %w[SLACK_CLIENT_ID SLACK_CLIENT_SECRET SLACK_SIGNING_SECRET],
      'instagram' => %w[INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN INSTAGRAM_API_VERSION ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT],
      'tiktok' => %w[TIKTOK_APP_ID TIKTOK_APP_SECRET TIKTOK_API_VERSION],
      'whatsapp_embedded' => %w[WHATSAPP_APP_ID WHATSAPP_APP_SECRET WHATSAPP_CONFIGURATION_ID WHATSAPP_API_VERSION],
      'notion' => %w[NOTION_CLIENT_ID NOTION_CLIENT_SECRET],
      'google' => %w[GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET GOOGLE_OAUTH_REDIRECT_URI ENABLE_GOOGLE_OAUTH_LOGIN],
      'google_calendar' => %w[GOOGLE_CALENDAR_CLIENT_ID GOOGLE_CALENDAR_CLIENT_SECRET],
      'microsoft_calendar' => %w[MICROSOFT_CALENDAR_CLIENT_ID MICROSOFT_CALENDAR_CLIENT_SECRET],
      'captain' => %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_MODEL CAPTAIN_OPEN_AI_ENDPOINT],
      'payphone' => PAYPHONE_CONFIGS
    }

    @allowed_configs = mapping.fetch(@config, general_configs)
  end

  def shopify_partner_config_errors
    return [] unless @config == 'shopify'

    saved_values = InstallationConfig.where(name: Shopify::PartnerConfiguration::KEYS).each_with_object({}) do |config, values|
      values[config.name] = config.value
    end
    submitted_values = params.fetch('app_config', {}).permit(*SHOPIFY_CONFIGS).to_h
    Shopify::PartnerConfiguration.validate_for_save!(saved_values.merge(submitted_values))
    []
  rescue Shopify::PartnerClient::ConfigurationError => e
    [e.message]
  end

  def success_notice
    message = "#{@config.titleize} settings updated successfully"
    return message unless restart_required_config_saved?

    "#{message.delete_suffix('.')}. Restart Chatwoot web and worker processes to apply this change everywhere."
  end

  def payphone_config_errors(submitted_values)
    saved_values = InstallationConfig.where(name: PAYPHONE_CONFIGS).each_with_object({}) do |config, values|
      values[config.name] = config.value
    end
    merged = merged_payphone_values(saved_values, submitted_values)
    errors = payphone_value_errors(merged)
    grace_days = Integer(merged['PAYPHONE_GRACE_DAYS'].to_s)
    errors << I18n.t('super_admin.payphone.errors.grace_days') if grace_days.negative?
    errors.concat(payphone_setup_errors(merged))
    errors
  rescue ArgumentError, TypeError
    [I18n.t('super_admin.payphone.errors.grace_days')]
  end

  def payphone_value_errors(values)
    errors = []
    errors << I18n.t('super_admin.payphone.errors.environment') unless %w[test production].include?(values['PAYPHONE_ENVIRONMENT'].to_s)
    errors << I18n.t('super_admin.payphone.errors.tax_rate') unless valid_percentage?(values['PAYPHONE_TAX_RATE'])
    errors << I18n.t('super_admin.payphone.errors.commission_rate') unless valid_percentage?(values['PAYPHONE_CARD_COMMISSION_RATE'])
    errors
  end

  def payphone_setup_errors(values)
    return Payphone::ConfigurationCheck.call(values: values).errors if ActiveModel::Type::Boolean.new.cast(values['ENABLE_PAYPHONE'])
    return [] if values['PAYPHONE_RESPONSE_URL'].blank?

    check_values = values.merge(
      'PAYPHONE_STORE_ID' => 'configured', 'PAYPHONE_TOKEN' => 'configured',
      'PAYPHONE_ENVIRONMENT' => 'test'
    )
    url_errors = %w[response_https response_domain frontend_domain_required].map do |key|
      I18n.t("super_admin.payphone.validation.#{key}")
    end
    Payphone::ConfigurationCheck.call(values: check_values).errors & url_errors
  end

  def initial_config_errors
    errors = shopify_partner_config_errors
    return errors unless @config == 'payphone'

    errors + payphone_config_errors(params.fetch('app_config', {}).permit(*PAYPHONE_CONFIGS).to_h)
  end

  def merged_payphone_values(saved_values, submitted_values)
    %w[PAYPHONE_TOKEN PAYPHONE_BOX_TOKEN].each do |key|
      submitted_values = submitted_values.except(key) if submitted_values[key].blank?
    end
    saved_values.merge(submitted_values)
  end

  def save_app_configs
    errors = []
    params['app_config'].each do |key, value|
      break if errors.any?
      next unless @allowed_configs.include?(key)
      next if %w[PAYPHONE_TOKEN PAYPHONE_BOX_TOKEN].include?(key) && value.blank?

      config = InstallationConfig.where(name: key).first_or_initialize(locked: false)
      config.value = value
      errors.concat(config.errors.full_messages) unless config.save
    end
    errors
  end

  def valid_percentage?(value)
    Float(value.to_s).between?(0, 100)
  rescue ArgumentError, TypeError
    false
  end

  def load_config_values
    @app_config = InstallationConfig.where(name: @allowed_configs)
                                    .pluck(:name, :serialized_value)
                                    .to_h
                                    .transform_values { |serialized_value| serialized_value['value'] }
    @payphone_tokens_configured = %w[PAYPHONE_TOKEN PAYPHONE_BOX_TOKEN].index_with do |key|
      InstallationConfig.find_by(name: key)&.serialized_value&.dig('value').present?
    end
    if @config == 'payphone'
      @app_config['PAYPHONE_TOKEN'] = nil
      @app_config['PAYPHONE_BOX_TOKEN'] = nil
    end
    @installation_configs = ConfigLoader.new.general_configs.each_with_object({}) do |config_hash, result|
      result[config_hash['name']] = config_hash.except('name')
    end
  end

  def success_flash
    restart_required_config_saved? ? { success: success_notice } : { notice: success_notice }
  end

  def restart_required_config_saved?
    params.fetch('app_config', {}).keys.intersect?(InstallationConfig::RESTART_REQUIRED_CONFIG_KEYS)
  end
end

SuperAdmin::AppConfigsController.prepend_mod_with('SuperAdmin::AppConfigsController')
