class Captain::Llm::PaginatedFaqGeneratorService < Llm::LegacyBaseOpenAiService
  include Integrations::LlmInstrumentation

  # Default pages per chunk - easily configurable
  DEFAULT_PAGES_PER_CHUNK = Llm::UnitCosts.fetch(:pdf, :pages_per_chunk)

  attr_reader :total_pages_processed, :iterations_completed

  def initialize(document, options = {})
    super()
    @document = document
    @language = options[:language] || 'english'
    @pages_per_chunk = (options[:pages_per_chunk] || DEFAULT_PAGES_PER_CHUNK).clamp(1, DEFAULT_PAGES_PER_CHUNK)
    @max_pages = [options[:max_pages] || Llm::UnitCosts.fetch(:pdf, :max_pages), Llm::UnitCosts.fetch(:pdf, :max_pages)].min
    @total_pages_processed = 0
    @iterations_completed = 0
    @model = Llm::FeatureRouter.resolve(feature: 'pdf_faq_generation', account: document.account)[:model]
  end

  def generate
    raise CustomExceptions::Pdf::FaqGenerationError, I18n.t('captain.documents.missing_openai_file_id') if @document&.openai_file_id.blank?

    generate_paginated_faqs
  end

  # Method to check if we should continue processing
  def should_continue_processing?(last_chunk_result)
    # Stop if we've hit the maximum iterations
    return false if @total_pages_processed >= Llm::UnitCosts.fetch(:pdf, :max_pages)

    # Stop if we've processed the maximum pages specified
    return false if @max_pages && @total_pages_processed >= @max_pages

    # Stop if the last chunk returned no FAQs (likely no more content)
    return false if last_chunk_result[:faqs].empty?

    # Stop if the LLM explicitly indicates no more content
    return false if last_chunk_result[:has_content] == false

    # Continue processing
    true
  end

  private

  def generate_paginated_faqs
    progress = @document.metadata.to_h.fetch('faq_generation', {})
    all_faqs = progress.fetch('faqs', [])
    @total_pages_processed = progress.fetch('pages_processed', 0)
    @iterations_completed = progress.fetch('iterations', 0)
    return all_faqs if progress['completed']

    current_page = @total_pages_processed + 1

    loop do
      end_page = calculate_end_page(current_page)
      chunk_result = process_chunk_and_update_state(current_page, end_page, all_faqs)

      completed = !should_continue_processing?(chunk_result) || all_faqs.size >= Llm::UnitCosts.fetch(:max_faqs_per_document)
      all_faqs = deduplicate_faqs(all_faqs).first(Llm::UnitCosts.fetch(:max_faqs_per_document))
      save_progress(all_faqs, completed)
      break if completed

      current_page = end_page + 1
    end

    deduplicate_faqs(all_faqs)
  rescue Llm::KnowledgeUsage::QuotaExceeded
    @document.update!(status: :in_progress, last_sync_error_code: 'usage_quota_exceeded')
    deduplicate_faqs(all_faqs)
  end

  def save_progress(faqs, completed)
    @document.update!(metadata: @document.metadata.to_h.merge('faq_generation' => {
                                                                'faqs' => faqs, 'pages_processed' => @total_pages_processed,
                                                                'iterations' => @iterations_completed, 'completed' => completed
                                                              }))
  end

  def calculate_end_page(current_page)
    end_page = current_page + @pages_per_chunk - 1
    @max_pages && end_page > @max_pages ? @max_pages : end_page
  end

  def process_chunk_and_update_state(current_page, end_page, all_faqs)
    chunk_result = process_page_chunk(current_page, end_page)
    chunk_faqs = chunk_result[:faqs]

    all_faqs.concat(chunk_faqs)
    @total_pages_processed = end_page
    @iterations_completed += 1

    chunk_result
  end

  def process_page_chunk(start_page, end_page)
    params = build_chunk_parameters(start_page, end_page)

    instrumentation_params = build_instrumentation_params(params, start_page, end_page)

    response = Llm::KnowledgeUsage.with_reserved(
      account: @document.account, feature: 'paginated_faq_generation', units: Llm::UnitCosts.fetch(:pdf, :units_per_chunk)
    ) do
      with_usage_recording(instrumentation_params) do
        instrument_llm_call(instrumentation_params) { request_completion(params) }
      end
    end

    result = parse_chunk_response(response)
    log_empty_response(document: @document, model: @model, pages: [start_page, end_page], response: response, result: result)
    { faqs: result['faqs'] || [], has_content: result['has_content'] != false }
  end

  def build_chunk_parameters(start_page, end_page)
    completion_parameters([{ role: 'user', content: build_user_content(start_page, end_page) }])
  end

  def completion_parameters(messages)
    format_options = Captain::ResponsesConfig.json_format_options(protocol: request_options[:protocol])
    return { model: @model, messages: messages, **format_options } unless request_options[:protocol] == :responses

    input = messages.map do |message|
      content = message[:content]
      if content.is_a?(Array)
        content = content.map do |item|
          item[:type] == 'file' ? { type: 'input_file', file_id: item[:file][:file_id] } : { type: 'input_text', text: item[:text] }
        end
      end
      message.merge(content: content)
    end
    params = { model: @model, input: input, store: false, **format_options }
    params[:reasoning] = request_options[:thinking] if request_options[:thinking]
    params
  end

  def request_completion(params)
    return @client.chat(parameters: params) unless request_options[:protocol] == :responses

    @client.json_post(path: 'responses', parameters: params)
  end

  def request_options
    @request_options ||= Captain::ResponsesConfig.options(model: @model, temperature: nil, feature: 'pdf_faq_generation')
  end

  def request_metadata
    Captain::ResponsesConfig.request_metadata(model: @model, feature: 'pdf_faq_generation')
  end

  def build_user_content(start_page, end_page)
    [
      {
        type: 'file',
        file: { file_id: @document.openai_file_id }
      },
      {
        type: 'text',
        text: page_chunk_prompt(start_page, end_page)
      }
    ]
  end

  def page_chunk_prompt(start_page, end_page)
    Captain::Llm::SystemPromptsService.paginated_faq_generator(start_page, end_page, @language)
  end

  def parse_chunk_response(response)
    content = completion_text(response)
    return { 'faqs' => [], 'has_content' => false } if content.nil?

    JSON.parse(sanitize_json_response(content))
  rescue JSON::ParserError => e
    Rails.logger.error "Error parsing chunk response: #{e.message}"
    { 'faqs' => [], 'has_content' => false }
  end

  def deduplicate_faqs(faqs)
    # Remove exact duplicates
    unique_faqs = faqs.uniq { |faq| faq['question'].downcase.strip }

    # Remove similar questions
    final_faqs = []
    unique_faqs.each do |faq|
      similar_exists = final_faqs.any? do |existing|
        similarity_score(existing['question'], faq['question']) > 0.85
      end

      final_faqs << faq unless similar_exists
    end

    Rails.logger.info "Deduplication: #{faqs.size} → #{final_faqs.size} FAQs"
    final_faqs
  end

  def similarity_score(str1, str2)
    words1 = str1.downcase.split(/\W+/).reject(&:empty?)
    words2 = str2.downcase.split(/\W+/).reject(&:empty?)
    common_words = words1 & words2
    total_words = (words1 + words2).uniq.size
    return 0 if total_words.zero?

    common_words.size.to_f / total_words
  end

  def build_instrumentation_params(params, start_page, end_page)
    {
      span_name: 'llm.paginated_faq_generation',
      account_id: @document&.account_id,
      feature_name: 'paginated_faq_generation',
      model: @model,
      provider: 'openai',
      messages: params[:messages] || params[:input],
      metadata: document_metadata.merge(request_metadata).merge(start_page: start_page, end_page: end_page, iteration: @iterations_completed + 1)
    }
  end

  def document_metadata
    @document&.to_llm_metadata || {}
  end
end
