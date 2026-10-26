require 'agents'

class Captain::Tools::HttpTool < Captain::Tools::BasePublicTool
  def initialize(assistant, custom_tool)
    @custom_tool = custom_tool
    super(assistant)
  end

  def active?
    @custom_tool.enabled?
  end

  def perform(tool_context, **params)
    return email_verification_failure(tool_context.state) if email_verification_required?(tool_context.state)

    params = fill_verified_email(params, tool_context.state)
    execute_tool_request(tool_context, params)
  rescue Variables::DeliveryRenderer::Error => e
    failure_result(I18n.t('variables.tool_render_failed', locale: @assistant.account.locale, path: e.path, status: e.status), tool_context.state)
  rescue StandardError => e
    Rails.logger.error("HttpTool execution error for #{@custom_tool.slug}: #{e.class} - #{e.message}")
    failure_result('An error occurred while executing the request', tool_context.state)
  end

  attr_reader :custom_tool

  def available_in_reply_suggestion?
    @custom_tool.http_method == 'GET'
  end

  private

  def execute_tool_request(tool_context, params)
    drops = variable_drops(tool_context.state)
    url = @custom_tool.build_request_url(params, drops: drops)
    body = @custom_tool.build_request_body(params, drops: drops)

    response_body = execute_http_request(url, body, tool_context)
    @custom_tool.format_response(response_body, drops: drops)
  end

  def email_verification_failure(state)
    failure_result(I18n.t('captain.custom_tool.email_verification_required'), state)
  end

  def email_verification_required?(state)
    @custom_tool.requires_email_verification? && !self.class.model_fills_verified_values? && state[:verified_email].blank?
  end

  def fill_verified_email(params, state)
    email_param = @custom_tool.verified_email_param
    return params if email_param.blank? || state[:verified_email].blank?

    params.merge(email_param => state[:verified_email])
  end

  def variable_drops(state)
    conversation = find_conversation(state)
    contact = conversation ? conversation.contact : find_contact(state)
    Variables::ContextFactory.new(
      account: @assistant.account, records: { conversation: conversation, contact: contact, assistant: @assistant }
    ).build(surface: 'captain')
  end

  def safe_to_run_after_new_customer_message?
    @custom_tool.http_method == 'GET'
  end

  # Limit response size to prevent memory exhaustion and match LLM token limits
  # 1MB of text ≈ 250K tokens, which exceeds most LLM context windows
  MAX_RESPONSE_SIZE = 1.megabyte

  # Route through SafeFetch so custom tool requests share the app's centralized HTTP
  # fetching (resolution, timeouts, response size limits, and redirect handling).
  def execute_http_request(url, body, tool_context)
    json_body = body if @custom_tool.http_method == 'POST'
    auth_headers = @custom_tool.build_auth_headers

    response_body = +''
    SafeFetch.fetch(
      url,
      method: @custom_tool.http_method == 'POST' ? :post : :get,
      body: json_body,
      headers: request_headers(tool_context, json_body, auth_headers),
      sensitive_headers: auth_headers.keys,
      http_basic_authentication: @custom_tool.build_basic_auth_credentials,
      max_bytes: MAX_RESPONSE_SIZE,
      validate_content_type: false
    ) { |result| response_body = result.tempfile.read }
    response_body
  end

  def request_headers(tool_context, json_body, auth_headers)
    headers = auth_headers.dup
    headers.merge!(@custom_tool.build_metadata_headers(tool_context&.state || {}))
    headers['Content-Type'] = 'application/json' if json_body.present?
    headers
  end
end
