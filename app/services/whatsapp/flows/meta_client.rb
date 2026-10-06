# The calls the flows make to Meta's Graph API for one WhatsApp Cloud channel (its WABA). One place for the Graph
# version, the token (the same one the templates use) and the error mapping, so the publish / version / test services
# only say what to do. Tokens never reach logs or error messages.
#
# Errors are raised as Error: `validation_errors` carries Meta's own list ({ error, message, ... }) when there is one,
# and `retryable?` is true for network trouble, 5xx and rate limits (the job retries those, never validation errors).
class Whatsapp::Flows::MetaClient
  GRAPH_VERSION = 'v22.0'.freeze
  TIMEOUT = 60
  RATE_LIMIT_CODES = [4, 17, 32, 613, 80_008].freeze

  class Error < StandardError
    attr_reader :http_status, :meta_code, :validation_errors

    def initialize(message, http_status: nil, meta_code: nil, retryable: false, validation_errors: [])
      super(message)
      @http_status = http_status
      @meta_code = meta_code
      @retryable = retryable
      @validation_errors = validation_errors
    end

    def retryable?
      @retryable
    end

    # What is stored in the publication: Meta's own list when it sent one, otherwise its message.
    def to_publication_errors
      validation_errors.presence || [{ 'error' => 'meta_error', 'message' => message }]
    end
  end

  def initialize(channel)
    @channel = channel
  end

  def waba_id
    @channel.provider_config['business_account_id']
  end

  # POST /{waba}/flows -> flow id. `clone_flow_id` makes the new flow start as a copy of another one.
  def create_flow(name:, categories:, clone_flow_id: nil)
    body = { name: name, categories: categories }
    body[:clone_flow_id] = clone_flow_id if clone_flow_id.present?
    request(:post, "#{base}/#{waba_id}/flows", json: body).fetch('id')
  end

  # POST /{flow}/assets with the Flow JSON as a file. Returns Meta's validation_errors ([] when it accepted it).
  def upload_flow_json(meta_flow_id, flow_json)
    response = request(:post, "#{base}/#{meta_flow_id}/assets", multipart: flow_json.to_json)
    Array(response['validation_errors'])
  end

  def publish(meta_flow_id)
    request(:post, "#{base}/#{meta_flow_id}/publish", json: {})
  end

  def deprecate(meta_flow_id)
    request(:post, "#{base}/#{meta_flow_id}/deprecate", json: {})
  end

  # Only drafts can be deleted in Meta.
  def delete_flow(meta_flow_id)
    request(:delete, "#{base}/#{meta_flow_id}")
  end

  # GET /{flow} -> { 'id', 'status', 'validation_errors', ... }
  def fetch_flow(meta_flow_id)
    request(:get, "#{base}/#{meta_flow_id}", query: { fields: 'id,name,status,validation_errors' })
  end

  # POST /{phone_number_id}/messages: messages go out through the number, not the WABA.
  def send_message(payload)
    phone_number_id = @channel.provider_config['phone_number_id']
    raise Error, 'The channel has no phone number id' if phone_number_id.blank?

    request(:post, "#{base}/#{phone_number_id}/messages", json: payload)
  end

  private

  def base
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{GRAPH_VERSION}"
  end

  def token
    @channel.template_access_token
  end

  def request(verb, url, json: nil, multipart: nil, query: nil)
    raise Error, 'The channel has no access token' if token.blank?

    options = { headers: { 'Authorization' => "Bearer #{token}" }, timeout: TIMEOUT }
    options[:query] = query if query
    apply_body(options, json, multipart)
    parse(HTTParty.public_send(verb, url, **options))
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
    raise Error.new("Meta unreachable (#{e.class.name})", retryable: true)
  end

  def apply_body(options, json, multipart)
    if json
      options[:headers]['Content-Type'] = 'application/json'
      options[:body] = json.to_json
    elsif multipart
      boundary = "flowjson#{SecureRandom.hex(8)}"
      options[:headers]['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      options[:body] = multipart_body(boundary, multipart)
    end
  end

  def multipart_body(boundary, flow_json)
    [
      "--#{boundary}", 'Content-Disposition: form-data; name="file"; filename="flow.json"', 'Content-Type: application/json', '', flow_json,
      "--#{boundary}", 'Content-Disposition: form-data; name="name"', '', 'flow.json',
      "--#{boundary}", 'Content-Disposition: form-data; name="asset_type"', '', 'FLOW_JSON',
      "--#{boundary}--", ''
    ].join("\r\n")
  end

  def parse(response)
    data = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    return data if response.success?

    raise_refusal(response.code, data['error'].is_a?(Hash) ? data['error'] : {})
  end

  def raise_refusal(http_status, error)
    code = error['code'].to_i
    Rails.logger.warn("[WHATSAPP FLOWS] Meta refused: HTTP #{http_status} code=#{code} subcode=#{error['error_subcode']}")
    raise Error.new(error['error_user_msg'].presence || error['message'].presence || "HTTP #{http_status}",
                    http_status: http_status, meta_code: code, retryable: http_status >= 500 || RATE_LIMIT_CODES.include?(code),
                    validation_errors: Array(error.dig('error_data', 'validation_errors')))
  end
end
