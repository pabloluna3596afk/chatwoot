# The example file of a template header (image, video, document). Meta wants a `header_handle` from the Resumable
# Upload API for it when a template is created, NOT the media_id used to send media (see Whatsapp::MediaUploadService).
#
# The upload belongs to an app, and the channel token already says which one: GET /debug_token with the token as both
# input and access token returns its app_id, so no installation setting is needed (WHATSAPP_APP_ID only exists for
# embedded signup, and a manually set up channel may belong to another app). Some token types cannot introspect
# themselves; then #available? is false and the form hides the media header option.
#
#   1. GET  /debug_token?input_token=T            -> data.app_id
#   2. POST /{app_id}/uploads?file_length&file_type&file_name  -> { id: 'upload:...' }
#   3. POST /{upload_id}  (Authorization: OAuth T, file_offset: 0, body = the bytes) -> { h: '4::...' }
#
# The token is only ever sent in a header and never logged.
class Whatsapp::TemplateHeaderHandleService
  API_VERSION = 'v22.0'.freeze
  CACHE_FOR = 1.hour
  TIMEOUT = 120

  class Error < StandardError; end

  def initialize(whatsapp_channel)
    @channel = whatsapp_channel
  end

  # Whether the channel token can upload header examples.
  def available?
    app_id.present?
  end

  # `file` is an uploaded file (tempfile, content_type, original_filename). Returns the handle.
  def upload!(file)
    raise Error, 'media_header_unavailable' unless available?

    bytes = file.tempfile.binmode.read
    session_id = open_session(bytes.bytesize, file.content_type, file.original_filename)
    upload_bytes(session_id, bytes)
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED => e
    Rails.logger.warn("[WHATSAPP] header upload failed: #{e.class}")
    raise Error, 'upload_failed'
  end

  private

  def app_id
    Rails.cache.fetch(cache_key, expires_in: CACHE_FOR, skip_nil: true) { discover_app_id }
  end

  def discover_app_id
    response = HTTParty.get("#{base}/debug_token", headers: auth_headers('Bearer'), query: { input_token: token }, timeout: TIMEOUT)
    response.success? ? response.dig('data', 'app_id').presence : nil
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED
    nil
  end

  def open_session(length, type, name)
    response = HTTParty.post("#{base}/#{app_id}/uploads", headers: auth_headers('Bearer'), timeout: TIMEOUT,
                                                          query: { file_length: length, file_type: type, file_name: name })
    id = response.parsed_response.is_a?(Hash) ? response.parsed_response['id'] : nil
    return id if response.success? && id.present?

    Rails.logger.warn("[WHATSAPP] header upload session refused: HTTP #{response.code}")
    raise Error, 'upload_failed'
  end

  def upload_bytes(session_id, bytes)
    headers = auth_headers('OAuth').merge('file_offset' => '0', 'Content-Type' => 'application/octet-stream')
    response = HTTParty.post("#{base}/#{session_id}", headers: headers, body: bytes, timeout: TIMEOUT)
    handle = response.parsed_response.is_a?(Hash) ? response.parsed_response['h'] : nil
    return handle if response.success? && handle.present?

    Rails.logger.warn("[WHATSAPP] header upload refused: HTTP #{response.code}")
    raise Error, 'upload_failed'
  end

  def token
    @channel.template_access_token
  end

  def auth_headers(scheme)
    { 'Authorization' => "#{scheme} #{token}" }
  end

  def base
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{API_VERSION}"
  end

  # The token is part of the key only as a digest, so rotating it re-checks the app.
  def cache_key
    "whatsapp:template_header_app:#{@channel.id}:#{Digest::SHA256.hexdigest(token.to_s)[0, 12]}"
  end
end
