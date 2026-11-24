# Allow audio attachments (call recordings, voice notes) to serve inline so the
# in-app <audio> player can stream them. Without this, ActiveStorage's blob model
# forces Content-Disposition: attachment for any MIME outside the default allowlist
# (images + PDF), which makes the browser download instead of play.
Rails.application.config.active_storage.content_types_allowed_inline += %w[
  audio/webm
  audio/ogg
  audio/opus
  audio/mpeg
  audio/mp4
  audio/x-m4a
  audio/wav
  audio/x-wav
]

module ActiveStorageDirectUploadMetadataFilter
  INTERNAL_METADATA_KEYS = %w[identified analyzed composed].freeze

  private

  def blob_args
    super.tap do |args|
      args[:metadata]&.except!(*INTERNAL_METADATA_KEYS, *INTERNAL_METADATA_KEYS.map(&:to_sym))
    end
  end
end

module ActiveStorageProxyRangeLimit
  STREAMING_MAX_RANGES = 1
  STREAMING_CHUNK_MAX_SIZE = 100.megabytes

  private

  def send_blob_byte_range_data(blob, range_header, disposition: nil)
    ranges = Rack::Utils.get_byte_ranges(range_header, blob.byte_size)
    return head(:range_not_satisfiable) unless valid_ranges?(ranges)

    super
  end

  def valid_ranges?(ranges)
    ranges.present? &&
      ranges.any?(&:present?) &&
      ranges.length <= STREAMING_MAX_RANGES &&
      ranges.sum { |range| range.end - range.begin } < STREAMING_CHUNK_MAX_SIZE
  end
end

module ActiveStorageOpusNormalizer
  extend ActiveSupport::Concern

  included do
    after_update :normalize_opus_content_type_for_playback, if: :saved_change_to_content_type?
  end

  def normalize_opus_content_type_for_playback
    return unless content_type == 'audio/opus'

    update_column(:content_type, 'audio/ogg')
  end
end

module ActiveStorageMessageDimensions
  extend ActiveSupport::Concern

  included do
    after_update_commit :broadcast_message_dimensions, if: :analyzed_dimensions_changed?
  end

  private

  def analyzed_dimensions_changed?
    return false unless analyzed? && saved_change_to_metadata?

    previous_metadata, current_metadata = saved_change_to_metadata
    dimensions = current_metadata.slice('width', 'height')
    dimensions.values_at('width', 'height').all?(&:present?) && dimensions != previous_metadata.slice('width', 'height')
  end

  def broadcast_message_dimensions
    attachment_ids = attachments.where(record_type: 'Attachment', name: 'file').select(:record_id)
    message_ids = ::Attachment.where(id: attachment_ids).select(:message_id)

    # Load fresh blobs for the payload, including the other attachments on each message.
    Message.where(id: message_ids).includes(attachments: { file_attachment: :blob }).find_each do |message|
      message.send_update_event unless message.deleted
    end
  end
end

# Block the default Rails direct-upload route. Dashboard and widget uploads both go
# through the scoped, authenticated /api/v1/... endpoints, so the bare route has no
# legitimate caller; leaving it open allows anonymous blob creation. Scoped subclasses
# call super and are exempt via the instance_of? check.
module ActiveStorageBareDirectUploadGuard
  extend ActiveSupport::Concern

  included do
    before_action :reject_bare_direct_upload
  end

  private

  def reject_bare_direct_upload
    head :forbidden if instance_of?(ActiveStorage::DirectUploadsController)
  end
end

Rails.application.config.to_prepare do
  unless ActiveStorage::DirectUploadsController < ActiveStorageDirectUploadMetadataFilter
    ActiveStorage::DirectUploadsController.prepend(ActiveStorageDirectUploadMetadataFilter)
  end

  unless ActiveStorage::DirectUploadsController.include?(ActiveStorageBareDirectUploadGuard)
    ActiveStorage::DirectUploadsController.include(ActiveStorageBareDirectUploadGuard)
  end

  ActiveStorage::Streaming.prepend(ActiveStorageProxyRangeLimit) unless ActiveStorage::Streaming < ActiveStorageProxyRangeLimit
  ActiveStorage::Blob.include(ActiveStorageOpusNormalizer) unless ActiveStorage::Blob < ActiveStorageOpusNormalizer
  ActiveStorage::Blob.include(ActiveStorageMessageDimensions) unless ActiveStorage::Blob < ActiveStorageMessageDimensions
end
