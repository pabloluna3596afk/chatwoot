# The file of a template whose header is an image, a video or a document, chosen when the template is sent.
#
# The file is uploaded once to Meta's media endpoint and the template is sent with its media_id, so Meta does not
# have to fetch a link for every recipient. What is kept in the header params (processed_params['header']):
#   media_id, media_blob (signed id of the stored copy), media_url (link to that copy, the fallback), media_name,
#   media_type, media_uploaded_at, media_phone_number_id.
# A media_id belongs to the number that uploaded it and Meta drops it after 30 days: past REFRESH_AFTER (or for another
# number) the stored copy is uploaded again.
#
# When Meta still refuses a media_id as expired or invalid, the provider re-uploads the stored copy once and resends,
# then falls back to the link (see Whatsapp::Providers::WhatsappCloudService#send_template). The id handed out is
# remembered with its copy and link for that (REMEMBER_FOR).
class Whatsapp::TemplateHeaderMedia
  # Template header limits: https://developers.facebook.com/docs/whatsapp/cloud-api/reference/media#supported-media-types
  FORMATS = {
    'IMAGE' => { content_types: %w[image/jpeg image/png], max_bytes: 5.megabytes },
    'VIDEO' => { content_types: %w[video/mp4 video/3gpp], max_bytes: 16.megabytes },
    'DOCUMENT' => { content_types: %w[application/pdf], max_bytes: 100.megabytes }
  }.freeze
  # Blob metadata: marks a stored copy as a header file, and when it was last chosen (see Whatsapp::HeaderMediaCleanupService).
  METADATA_KEY = 'whatsapp_header_media'.freeze
  LAST_USED_KEY = 'whatsapp_header_last_used_at'.freeze
  REFRESH_AFTER = 25.days
  REMEMBER_FOR = 32.days
  # Cloud API errors for a media that cannot be downloaded or was not uploaded (the id may still be refused with a
  # generic error that names the media, see .media_error?).
  MEDIA_ERROR_CODES = [131_052, 131_053].freeze

  # The file does not fit the header: `reason` is a stable code the API returns (invalid_type, too_large, empty).
  class InvalidFile < StandardError
    attr_reader :reason

    def initialize(reason, message)
      @reason = reason
      super(message)
    end
  end

  class << self
    def format_for(format)
      FORMATS[format.to_s.upcase]
    end

    def validate!(format, content_type, byte_size)
      rules = format_for(format)
      raise InvalidFile.new('invalid_format', "unsupported header format #{format}") if rules.nil?
      raise InvalidFile.new('empty', 'the file is empty') unless byte_size.to_i.positive?

      unless rules[:content_types].include?(content_type)
        raise InvalidFile.new('invalid_type', "#{content_type} is not accepted for a #{format.to_s.downcase} header")
      end
      raise InvalidFile.new('too_large', "the file exceeds #{rules[:max_bytes] / 1.megabyte} MB") if byte_size > rules[:max_bytes]
    end

    # Validates the file, keeps a copy (the one already kept when the same file was chosen before: one copy per file,
    # not one per upload) and uploads it to Meta. Returns the header params to save. Raises InvalidFile or
    # Whatsapp::MediaUploadService::UploadError.
    def store_and_upload!(channel, format:, file:)
      content_type = Marcel::MimeType.for(file.tempfile, name: file.original_filename, declared_type: file.content_type).to_s
      validate!(format, content_type, file.size)

      blob = reusable_blob(channel, file) || store(channel, file, content_type)
      header_params(channel, blob, Whatsapp::MediaUploadService.upload_blob!(channel, blob), format)
    end

    # The media_id to send: the saved one while it is valid for this number, a new one from the stored copy when it
    # is older than REFRESH_AFTER, nil when there is none (the link is used).
    def media_id_for(channel, header)
      media_id = header['media_id']
      return if media_id.blank?

      id = usable_media_id(channel, header, media_id)
      remember(channel, id, header) if id.present?
      id
    end

    # The stored copy of the header file of a template message (its template_params), or nil: the chat shows it
    # as the attachment of that message, sharing the blob (no second copy).
    def blob_for_message(template_params, account_id)
      processed = template_params.is_a?(Hash) ? template_params['processed_params'] : nil
      header = processed.is_a?(Hash) ? processed['header'] : nil
      signed_id = header.is_a?(Hash) ? header['media_blob'] : nil
      return if signed_id.blank?

      blob = ActiveStorage::Blob.find_signed(signed_id)
      blob if blob&.metadata&.dig('account_id') == account_id
    end

    # How the chat shows a header file: as an image, a video or a document.
    def attachment_file_type(blob)
      case blob.content_type.to_s.split('/').first
      when 'image' then :image
      when 'video' then :video
      else :file
      end
    end

    # Whether Meta's error response says the header media was refused.
    def media_error?(parsed_response)
      error = parsed_response.is_a?(Hash) ? parsed_response['error'] : nil
      return false unless error.is_a?(Hash)

      MEDIA_ERROR_CODES.include?(error['code'].to_i) || error.values_at('message', 'error_data').join(' ').match?(/media/i)
    end

    # The header media parameter of the template components ({ type: 'image', image: { id: } }), or nil.
    def header_media_parameter(components)
      header = Array(components).find { |component| component[:type].to_s == 'header' }
      Array(header&.dig(:parameters)).find { |parameter| parameter.is_a?(Hash) && parameter.dig(parameter[:type]&.to_sym, :id).present? }
    end

    # A new media_id for a refused one, uploaded again from the stored copy; nil when there is no copy or the upload fails.
    def reupload(channel, media_id)
      entry = Rails.cache.read(cache_key(channel, media_id))
      blob = entry && stored_blob(channel, entry['blob'])
      return if blob.nil?

      new_id = Whatsapp::MediaUploadService.upload_blob!(channel, blob)
      Rails.cache.write(cache_key(channel, new_id), entry, expires_in: REMEMBER_FOR)
      new_id
    rescue Whatsapp::MediaUploadService::UploadError => e
      Rails.logger.warn("[WHATSAPP] Header media re-upload failed for channel #{channel.id}: #{e.message}")
      nil
    end

    # The link of the stored copy of a refused media_id (the last resort), or nil.
    def link_for(channel, media_id)
      Rails.cache.read(cache_key(channel, media_id))&.dig('url').presence
    end

    private

    def store(channel, file, content_type)
      ActiveStorage::Blob.create_and_upload!(
        io: file.tempfile, filename: file.original_filename, content_type: content_type,
        metadata: { 'account_id' => channel.account_id, METADATA_KEY => true, LAST_USED_KEY => Time.current.iso8601 }
      )
    end

    # The copy of this same file (same bytes and name) of the account, marked as used now so it is not cleaned up.
    def reusable_blob(channel, file)
      checksum = Digest::MD5.file(file.tempfile.path).base64digest
      blob = ActiveStorage::Blob.where(checksum: checksum, filename: file.original_filename).find do |candidate|
        candidate.metadata['account_id'] == channel.account_id && candidate.metadata[METADATA_KEY]
      end
      blob&.tap { |found| found.update!(metadata: found.metadata.merge(LAST_USED_KEY => Time.current.iso8601)) }
    end

    def header_params(channel, blob, media_id, format)
      {
        'media_id' => media_id,
        'media_blob' => blob.signed_id,
        'media_url' => Rails.application.routes.url_helpers.rails_blob_url(blob, **FrontendUrl.default_url_options),
        'media_name' => blob.filename.to_s,
        'media_type' => format.to_s.downcase,
        'media_uploaded_at' => Time.current.iso8601,
        'media_phone_number_id' => channel.provider_config['phone_number_id'].to_s
      }
    end

    def usable_media_id(channel, header, media_id)
      return media_id if fresh?(channel, header)

      blob = stored_blob(channel, header['media_blob'])
      return same_number?(channel, header) ? media_id : nil if blob.nil?

      refreshed_media_id(channel, blob)
    end

    def remember(channel, media_id, header)
      entry = { 'blob' => header['media_blob'], 'url' => header['media_url'] }
      Rails.cache.write(cache_key(channel, media_id), entry, expires_in: REMEMBER_FOR, unless_exist: true)
    end

    def cache_key(channel, media_id)
      "whatsapp_header_media_entry:#{channel.id}:#{media_id}"
    end

    def fresh?(channel, header)
      uploaded_at = Time.zone.parse(header['media_uploaded_at'].to_s)
      uploaded_at.present? && uploaded_at > REFRESH_AFTER.ago && same_number?(channel, header)
    end

    def same_number?(channel, header)
      header['media_phone_number_id'].to_s == channel.provider_config['phone_number_id'].to_s
    end

    def stored_blob(channel, signed_id)
      return if signed_id.blank?

      blob = ActiveStorage::Blob.find_signed(signed_id)
      blob if blob&.metadata&.dig('account_id') == channel.account_id
    end

    # One upload per file and number, not one per recipient of a campaign.
    def refreshed_media_id(channel, blob)
      Rails.cache.fetch("whatsapp_header_media:#{channel.id}:#{blob.id}", expires_in: REFRESH_AFTER - 1.day) do
        Whatsapp::MediaUploadService.upload_blob!(channel, blob)
      end
    rescue Whatsapp::MediaUploadService::UploadError => e
      Rails.logger.warn("[WHATSAPP] Header media refresh failed for channel #{channel.id}: #{e.message}")
      nil
    end
  end
end
