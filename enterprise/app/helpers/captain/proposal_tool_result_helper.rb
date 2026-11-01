module Captain::ProposalToolResultHelper
  private

  def persist_tool_result(result, pending_call, copilot_thread:)
    return unless pending_call

    failed_proposal = copilot_thread.present? && pending_call[:tool_call].name.to_s == 'propose_action' && tool_result_error?(result)
    return pending_call[:thinking_message]&.destroy! if failed_proposal

    persist_tool_completion(result, pending_call)
  end
end
