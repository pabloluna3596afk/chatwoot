# The file of a template whose header is an image, a video or a document, chosen when the template is sent.
#
# The file is uploaded once to Meta's media endpoint and the template is sent with its media_id, so Meta does not
# have to fetch a link for every recipient. What is kept in the header params (processed_params['header']):
#   media_id, media_blob (signed id of the stored copy), media_url (link to that copy, the fallback), media_name,
#   media_type, media_uploaded_at, media_phone_number_id.
# A media_id belongs to the number that uploaded it and Meta drops it after 30 days: past REFRESH_AFTER (or for another
# number) the stored copy is uploaded again.
class Whatsapp::TemplateHeaderMedia
  # Template header limits: https://developers.facebook.com/docs/whatsapp/cloud-api/reference/media#supported-media-types
  FORMATS = {
    'IMAGE' => { content_types: %w[image/jpeg image/png], max_bytes: 5.megabytes },
    'VIDEO' => { content_types: %w[video/mp4 video/3gpp], max_bytes: 16.megabytes },
    'DOCUMENT' => { content_types: %w[application/pdf], max_bytes: 100.megabytes }
  }.freeze
  REFRESH_AFTER = 25.days

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

    # Validates the file, keeps a copy and uploads it to Meta. Returns the header params to save. Raises InvalidFile
    # or Whatsapp::MediaUploadService::UploadError.
    def store_and_upload!(channel, format:, file:)
      content_type = Marcel::MimeType.for(file.tempfile, name: file.original_filename, declared_type: file.content_type).to_s
      validate!(format, content_type, file.size)

      blob = ActiveStorage::Blob.create_and_upload!(
        io: file.tempfile, filename: file.original_filename, content_type: content_type,
        metadata: { 'account_id' => channel.account_id, 'whatsapp_header_media' => true }
      )
      media_id = Whatsapp::MediaUploadService.upload_blob!(channel, blob)

      {
        'media_id' => media_id,
        'media_blob' => blob.signed_id,
        'media_url' => Rails.application.routes.url_helpers.url_for(blob, **FrontendUrl.default_url_options),
        'media_name' => blob.filename.to_s,
        'media_type' => format.to_s.downcase,
        'media_uploaded_at' => Time.current.iso8601,
        'media_phone_number_id' => channel.provider_config['phone_number_id'].to_s
      }
    end

    # The media_id to send: the saved one while it is valid for this number, a new one from the stored copy when it
    # is older than REFRESH_AFTER, nil when there is none (the link is used).
    def media_id_for(channel, header)
      media_id = header['media_id']
      return if media_id.blank?
      return media_id if fresh?(channel, header)

      blob = stored_blob(channel, header['media_blob'])
      return same_number?(channel, header) ? media_id : nil if blob.nil?

      refreshed_media_id(channel, blob)
    end

    private

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
