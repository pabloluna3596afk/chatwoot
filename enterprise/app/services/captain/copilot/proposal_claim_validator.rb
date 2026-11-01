class Captain::Copilot::ProposalClaimValidator
  CLAIM_PATTERN = /
    (?:proposal|propuesta).{0,60}(?:created|prepared|pending|ready|waiting|cread|preparad|pendiente|lista|espera)
    |
    (?:created|prepared|cread|preparad).{0,40}(?:proposal|propuesta)
  /ix
  CORRECTED_CONTENT = 'No hay una propuesta creada. No se aplicó ningún cambio. ' \
                      'Usa list_labels para elegir una etiqueta y vuelve a intentarlo.'.freeze

  def self.call(thread:, proposal_tool:, result:)
    new(thread: thread, proposal_tool: proposal_tool, result: result).call
  end

  def initialize(thread:, proposal_tool:, result:)
    @thread = thread
    @proposal_tool = proposal_tool
    @result = result
  end

  def call
    return @result unless claim_without_persisted_proposal?

    corrected_result
  end

  private

  def claim_without_persisted_proposal?
    return false unless @thread && content.match?(CLAIM_PATTERN)

    !@thread.copilot_action_items.exists?(id: @proposal_tool&.created_proposal_ids || [])
  end

  def content
    return '' unless @result.is_a?(Hash)

    @result['content'] || @result[:content] || ''
  end

  def corrected_result
    content_key = @result.key?('content') ? 'content' : :content
    @result[content_key] = CORRECTED_CONTENT
    @thread.copilot_messages.assistant.order(id: :desc).first&.update!(message: @result)
    @result
  end
end
