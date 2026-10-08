# Creates, edits, deletes and reads the message templates of a WhatsApp Cloud channel in Meta (the WABA's
# /message_templates), for the templates page. Follows Whatsapp::CsatTemplateService (same endpoints and auth), but is
# generic: any name, language, category and components, built by Whatsapp::TemplateComponentsBuilder.
#
# Meta rules the callers can run into (the dashboard shows them too):
#  - an approved template can be edited at most 10 times in 30 days and once in 24 hours, is reviewed again after an
#    edit, and its category cannot change;
#  - a deleted name and language are blocked for 30 days;
#  - 250 templates per account while the business is not verified.
#
# Errors are raised as Error with a stable `code` (an i18n key under whatsapp_templates.errors) and the Meta detail.
class Whatsapp::TemplateManagementService
  API_VERSION = 'v22.0'.freeze
  FIELDS = 'id,name,status,category,language,components,parameter_format,last_updated_time,rejected_reason,quality_score'.freeze
  TIMEOUT = 60
  LIBRARY_PAGE = 25
  LIBRARY_FIELDS = %w[id name language category topic usecase industry header body body_params buttons].freeze
  LIBRARY_REGIONAL_LANGUAGES = %w[en_US pt_BR].freeze
  LIBRARY_LANGUAGE_ERROR = /language.*not available for using library templates/i

  # Meta error subcodes / messages -> our code. Anything else is `meta_error` (Meta's own text is kept as `detail`).
  SUBCODES = { 2_388_023 => 'name_locked', 2_388_024 => 'name_exists' }.freeze
  CODES = { 190 => 'token_invalid', 10 => 'permission_denied', 200 => 'permission_denied', 3 => 'permission_denied',
            4 => 'rate_limited', 17 => 'rate_limited', 32 => 'rate_limited', 613 => 'rate_limited', 80_008 => 'rate_limited',
            132_001 => 'not_found' }.freeze
  MESSAGES = [
    [/already exists/i, 'name_exists'],
    [/(being deleted|deleted.*(30|thirty)|wait.*(30|thirty|4 weeks))/i, 'name_locked'],
    [/(edit.*(limit|once|10 times|24 hours|30 days)|too many edits|can only be edited)/i, 'edit_limit'],
    [/category.*(cannot|can't|not allowed|change)|(cannot|can't).*change.*category/i, 'category_locked'],
    [/(template limit|maximum (number )?of (message )?templates|reached.*templates)/i, 'template_limit']
  ].freeze

  class Error < StandardError
    attr_reader :code, :detail, :meta_code, :http_status, :meta_message, :error_subcode, :error_user_msg

    def initialize(code, detail: nil, meta_code: nil, http_status: nil, **meta)
      @code = code
      @detail = detail
      @meta_code = meta_code
      @http_status = http_status
      @meta_message = meta[:meta_message]
      @error_subcode = meta[:error_subcode]
      @error_user_msg = meta[:error_user_msg]
      super("#{code}#{detail ? ": #{detail}" : ''}")
    end
  end

  def initialize(whatsapp_channel)
    @channel = whatsapp_channel
  end

  # Returns { id:, status:, category: }. `components` come from TemplateComponentsBuilder.
  def create(name:, language:, category:, components:, parameter_format: nil)
    @template_name = name
    body = { name: name, language: language, category: category, components: components }
    body[:parameter_format] = parameter_format if parameter_format == 'NAMED'
    response = request(:post, "#{waba_path}/message_templates", body: body)
    finish(response, 'id', 'status', 'category')
  end

  # An edit sends the components (and the category, which Meta only accepts while the template is not approved).
  def update(template_id, components:, category: nil, **identity)
    original = fetch(template_id)
    @template_name = original[:name]
    Whatsapp::TemplateEditValidator.new(original).validate!(components, category: category, **identity)
    body = { components: components }
    body[:category] = category if category.present?
    response = request(:post, "#{base}/#{template_id}", body: body)
    raise_failure(response) unless response.success? && response.parsed_response.is_a?(Hash) && response.parsed_response['success']

    sync
    { id: template_id.to_s, status: 'PENDING' }
  end

  # Always with the hsm_id when it is known: the name alone deletes every language of the template.
  def delete(name:, hsm_id: nil)
    query = { name: name }
    query[:hsm_id] = hsm_id if hsm_id.present?
    response = request(:delete, "#{waba_path}/message_templates", query: query)
    raise_failure(response) unless response.success?

    sync
    { deleted: true }
  end

  # Meta's Template Library: ready-made utility templates (fixed text, only their parameters change).
  # Returns { templates: [...], next: cursor or nil, language_used: locale or nil (all languages) }.
  # `filters` are search, language, topic, usecase, industry and after (the cursor).
  def library(limit: LIBRARY_PAGE, **filters)
    query = filters.slice(:search, :language, :topic, :usecase, :industry, :after).merge(limit: limit).compact_blank
    query[:language] = library_language(query[:language]) if query[:language]
    data, language = library_response(query)
    { templates: Array(data['data']).map { |entry| entry.slice(*LIBRARY_FIELDS) },
      next: data.dig('paging', 'cursors', 'after'), language_used: language }
  end

  # Creates a template from the library by its name; `button_inputs` are the values some of its buttons ask for
  # (a phone number, a URL), as Meta takes them in library_template_button_inputs.
  def create_from_library(library_template_name:, name:, language:, category:, button_inputs: [])
    language = library_language(language)
    body = { name: name, language: language, category: category, library_template_name: library_template_name }
    body[:library_template_button_inputs] = button_inputs if button_inputs.present?
    response = request(:post, "#{waba_path}/message_templates", body: body)
    finish(response, 'id', 'status', 'category').merge(language_used: language)
  end

  # The live state of one template, with the rejection reason the synced list does not carry.
  def fetch(template_id)
    response = request(:get, "#{base}/#{template_id}", query: { fields: FIELDS })
    raise_failure(response) unless response.success? && response.parsed_response.is_a?(Hash)

    data = response.parsed_response
    { id: data['id'], name: data['name'], status: data['status'], category: data['category'], language: data['language'],
      parameter_format: data['parameter_format'], last_updated_time: data['last_updated_time'],
      rejected_reason: data['rejected_reason'], quality_score: data.dig('quality_score', 'score'), components: data['components'] }
  end

  private

  def library_language(language)
    LIBRARY_REGIONAL_LANGUAGES.include?(language) ? language : language.split('_').first
  end

  def library_response(query)
    [query[:language], 'en_US', nil].uniq.each do |language|
      return [request_library(query, language), language]
    rescue Error => e
      raise unless language && library_language_error?(e)
    end
  end

  def request_library(query, language)
    response = request(:get, "#{base}/message_template_library", query: query.merge(language: language).compact)
    raise_failure(response) unless response.success? && response.parsed_response.is_a?(Hash)

    response.parsed_response
  end

  def library_language_error?(error)
    error.meta_code == 100 && error.detail.to_s.match?(LIBRARY_LANGUAGE_ERROR)
  end

  def finish(response, *keys)
    raise_failure(response) unless response.success? && response.parsed_response.is_a?(Hash)

    sync
    response.parsed_response.slice(*keys).symbolize_keys
  end

  def request(verb, url, body: nil, query: nil)
    @request_body = body
    options = { headers: headers, timeout: TIMEOUT }
    options[:body] = body.to_json if body
    options[:query] = query if query
    HTTParty.public_send(verb, url, **options)
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED => e
    Rails.logger.warn("[WHATSAPP] template request failed: #{e.class}")
    raise Error.new('meta_unreachable', detail: e.class.name)
  end

  def raise_failure(response)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    error = {} unless error.is_a?(Hash)
    safe = error.slice('message', 'code', 'error_subcode', 'error_user_msg').transform_values do |value|
      value.is_a?(String) ? redact_error_text(value) : value
    end
    detail = safe['error_user_msg'].presence || safe['message'].presence
    Rails.logger.warn("[WHATSAPP] template=#{@template_name} HTTP #{response.code} error=#{safe.to_json}")
    raise Error.new(
      error_code_for(error, detail), detail: detail, meta_code: safe['code'], http_status: response.code,
                                     meta_message: safe['message'], error_subcode: safe['error_subcode'], error_user_msg: safe['error_user_msg']
    )
  end

  # Meta can echo a submitted value in an error. Never log template text, sample data or credentials.
  def redact_error_text(text)
    values = [@channel.template_access_token, *request_values(@request_body)].compact_blank
    values.sort_by { |value| -value.length }.reduce(text) { |result, value| result.gsub(value, '[REDACTED]') }
          .gsub(/Bearer\s+\S+|(?:access_token|appsecret_proof|client_secret)=\S+/i, '[REDACTED]')
  end

  def request_values(value)
    case value
    when Hash
      value.except(:name, :language, :category, :type, :format, :parameter_format).values.flat_map { |item| request_values(item) }
    when Array then value.flat_map { |item| request_values(item) }
    when String then [value]
    else []
    end
  end

  def error_code_for(error, detail)
    SUBCODES[error['error_subcode'].to_i] ||
      MESSAGES.find { |pattern, _code| detail.to_s.match?(pattern) }&.last ||
      CODES[error['code'].to_i] ||
      'meta_error'
  end

  # The templates list is what the dashboard reads, so refresh it after every change (best effort: the change
  # itself already happened in Meta).
  def sync
    @channel.provider_service.sync_templates
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP] template sync after a change failed: #{e.class}")
  end

  def waba_path
    "#{base}/#{@channel.provider_config['business_account_id']}"
  end

  def base
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{API_VERSION}"
  end

  def headers
    { 'Authorization' => "Bearer #{@channel.template_access_token}", 'Content-Type' => 'application/json' }
  end
end
