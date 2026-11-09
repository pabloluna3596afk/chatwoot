class Captain::Documents::ResponseBuilderJob < ApplicationJob
  queue_as :low

  def perform(document, options = {})
    signature = source_signature(document)
    return if document.metadata.to_h.dig('faq_generation', 'source_signature') == signature

    document.update!(last_sync_error_code: nil) if document.last_sync_error_code == 'usage_quota_exceeded'
    faqs = generate_faqs(document, options)
    return unless replace_generated_responses(document, faqs)

    mark_completed(document, signature)
    # Only after success: a failed run is retried and still needs the uploaded file.
    delete_pdf_from_openai(document) if document.pdf_document? && document.openai_file_id.present?
  rescue Llm::KnowledgeUsage::QuotaExceeded
    document.update!(status: :in_progress, last_sync_error_code: 'usage_quota_exceeded')
  end

  private

  def source_signature(document)
    document.pdf_document? ? document.external_link : Digest::SHA256.hexdigest(document.content.to_s)
  end

  def mark_completed(document, signature)
    progress = document.metadata.to_h.fetch('faq_generation', {})
    document.update!(status: :available, last_sync_error_code: nil,
                     metadata: document.metadata.to_h.merge('faq_generation' => progress.merge('source_signature' => signature)))
  end

  def replace_generated_responses(document, faqs)
    return false if faqs.empty? && document.last_sync_error_code == 'usage_quota_exceeded'

    reset_previous_responses(document)
    capacity = [Llm::UnitCosts.fetch(:max_faqs_per_document) - document.responses.count, 0].max
    create_responses_from_faqs(faqs.first(capacity), document)
    document.last_sync_error_code != 'usage_quota_exceeded'
  end

  def generate_faqs(document, options)
    if should_use_pagination?(document)
      generate_paginated_faqs(document, options)
    else
      generate_standard_faqs(document)
    end
  end

  def generate_paginated_faqs(document, options)
    service = build_paginated_service(document, options)
    faqs = service.generate
    store_paginated_metadata(document, service, faqs)
    faqs
  end

  def generate_standard_faqs(document)
    progress = document.metadata.to_h.fetch('faq_generation', {})
    signature = source_signature(document)
    return progress.fetch('faqs') if progress['content_fingerprint'] == signature

    faqs = Captain::Llm::FaqGeneratorService.new(document: document).generate
    document.update!(metadata: document.metadata.to_h.merge('faq_generation' => { 'content_fingerprint' => signature, 'faqs' => faqs }))
    faqs
  end

  def delete_pdf_from_openai(document)
    Captain::Llm::PdfProcessingService.new(document).delete_openai_file
  rescue StandardError => e
    Rails.logger.error("[Captain::Documents::ResponseBuilderJob] Failed to clean up OpenAI PDF for document #{document.id}: #{e.message}")
  end

  def build_paginated_service(document, options)
    Captain::Llm::PaginatedFaqGeneratorService.new(
      document,
      pages_per_chunk: options[:pages_per_chunk],
      max_pages: options[:max_pages],
      language: document.account.locale_english_name
    )
  end

  def store_paginated_metadata(document, service, faqs)
    document.update!(
      metadata: (document.metadata || {}).merge(
        'faq_generation' => document.metadata.to_h.fetch('faq_generation', {}).merge(
          'method' => 'paginated',
          'pages_processed' => service.total_pages_processed,
          'iterations' => service.iterations_completed,
          'empty_result' => faqs.empty?,
          'timestamp' => Time.current.iso8601
        )
      )
    )
  end

  def create_responses_from_faqs(faqs, document)
    faqs.each { |faq| create_response(faq, document) }
  end

  def should_use_pagination?(document)
    # Auto-detect when to use pagination
    # For now, use pagination for PDFs with OpenAI file ID
    document.pdf_document? && document.openai_file_id.present?
  end

  def reset_previous_responses(response_document)
    response_document.responses.where(edited: false).destroy_all
  end

  def create_response(faq, document)
    document.responses.create!(
      question: faq['question'],
      answer: faq['answer'],
      assistant: document.assistant,
      documentable: document
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error I18n.t('captain.documents.response_creation_error', error: e.message)
  end
end
