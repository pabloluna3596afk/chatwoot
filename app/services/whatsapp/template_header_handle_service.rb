# The example file of a template header (image, video, document). Meta wants a `header_handle` from the Resumable
# Upload API for it when a template is created, NOT the media_id used to send media (see Whatsapp::MediaUploadService).
#
# The upload belongs to an app, and it has to be the app behind the channel token. It is found, in this order:
#   1. GET /debug_token?input_token=T (T as both input and access token) -> data.app_id. User tokens can introspect
#      themselves; the permanent token of a system user cannot (Meta answers 400, "must provide an app access token").
#   2. WHATSAPP_APP_ID of the installation (embedded signup), when set.
#   3. GET /{waba_id}/subscribed_apps -> the apps subscribed to the WhatsApp Business Account, one of which is the app
#      of the channel (the one whose webhook receives its messages).
# Each candidate is PROBED before it is trusted: opening an upload session for it (nothing is uploaded) shows whether
# this token may upload to that app. When none can, #unavailable_reason says why and the form hides the media header.
#
#   POST /{app_id}/uploads?file_length&file_type&file_name  -> { id: 'upload:...' }
#   POST /{upload_id}  (Authorization: OAuth T, file_offset: 0, body = the bytes) -> { h: '4::...' }
#
# The token is only ever sent in a header and never logged.
class Whatsapp::TemplateHeaderHandleService
  API_VERSION = 'v22.0'.freeze
  CACHE_FOR = 1.hour
  RETRY_AFTER = 5.minutes
  TIMEOUT = 120

  class Error < StandardError; end

  def initialize(whatsapp_channel)
    @channel = whatsapp_channel
  end

  # Whether the channel token can upload header examples.
  def available?
    app_id.present?
  end

  # Why it cannot (a stable code for the form), nil when it can: 'app_not_found' (no app could be found for the
  # token) or 'upload_refused' (apps were found, but Meta does not let this token upload to them).
  def unavailable_reason
    discovery['reason']
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
    discovery['app_id']
  end

  # { 'app_id' => ..., 'reason' => ... }: kept for an hour when an app was found, 5 minutes when not.
  def discovery
    @discovery ||= Rails.cache.read(cache_key) || discover.tap do |entry|
      Rails.cache.write(cache_key, entry, expires_in: entry['app_id'] ? CACHE_FOR : RETRY_AFTER)
    end
  end

  def discover
    tried = []
    # Each source is only asked when the ones before it gave no app that can upload.
    [-> { token_app_id }, -> { configured_app_id }, -> { subscribed_app_ids }].each do |source|
      Array(source.call).compact_blank.each do |candidate|
        next if tried.include?(candidate)

        tried << candidate
        return { 'app_id' => candidate } if session_opens?(candidate)
      end
    end
    { 'reason' => tried.empty? ? 'app_not_found' : 'upload_refused' }
  end

  def token_app_id
    graph_get('debug_token', input_token: token)&.dig('data', 'app_id')
  end

  def subscribed_app_ids
    waba_id = @channel.provider_config['business_account_id'].presence
    return [] unless waba_id

    Array(graph_get("#{waba_id}/subscribed_apps")&.dig('data')).filter_map do |entry|
      entry.dig('whatsapp_business_api_data', 'id') if entry.is_a?(Hash)
    end
  end

  def configured_app_id
    GlobalConfigService.load('WHATSAPP_APP_ID', '').presence
  end

  def graph_get(path, query = {})
    response = HTTParty.get("#{base}/#{path}", headers: auth_headers('Bearer'), query: query, timeout: TIMEOUT)
    response.success? && response.parsed_response.is_a?(Hash) ? response.parsed_response : nil
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED
    nil
  end

  # Whether Meta lets this token open an upload session on the app (a one byte session that is never filled).
  def session_opens?(candidate)
    session_id_for(candidate, 1, 'image/jpeg', 'probe.jpg').present?
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED
    false
  end

  def open_session(length, type, name)
    id = session_id_for(app_id, length, type, name)
    return id if id.present?

    Rails.logger.warn('[WHATSAPP] header upload session refused')
    raise Error, 'upload_failed'
  end

  def session_id_for(app, length, type, name)
    response = HTTParty.post("#{base}/#{app}/uploads", headers: auth_headers('Bearer'), timeout: TIMEOUT,
                                                       query: { file_length: length, file_type: type, file_name: name })
    id = response.parsed_response.is_a?(Hash) ? response.parsed_response['id'] : nil
    response.success? ? id : nil
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
