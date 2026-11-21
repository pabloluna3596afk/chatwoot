class WhatsappTemplateDraftSerializer
  DRAFT_FIELDS = %w[id title name language category parameter_format waba_id preferred_channel_id source_draft_id source_remote_id
                    created_by_id updated_by_id lock_version archived_at created_at updated_at definition variable_bindings].freeze
  SUBMISSION_FIELDS = %w[id revision waba_id name language actor_id status remote_id remote_status remote_category remote_reason
                         error_details request_count next_retry_at submitted_at created_at updated_at].freeze

  def self.render(draft)
    draft.attributes.slice(*DRAFT_FIELDS).merge(
      'status' => draft.submissions.find { |submission| submission.revision == draft.lock_version }&.status || 'draft',
      'media' => if draft.media.attached?
                   { 'filename' => draft.media.filename.to_s, 'content_type' => draft.media.content_type,
                     'byte_size' => draft.media.byte_size }
                 end,
      'submissions' => draft.submissions.sort_by(&:revision).reverse.map { |submission| submission.attributes.slice(*SUBMISSION_FIELDS) }
    )
  end
end
