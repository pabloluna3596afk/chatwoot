class Captain::Decisions::TechnicalSummary
  def self.build(user:, account_user:, details:, applicable: true)
    fields = if user.is_a?(SuperAdmin)
               %w[model credits_consumed cost]
             elsif account_user&.administrator?
               %w[credits_consumed]
             else
               []
             end
    fields.index_with { |field| value(details, field, applicable) }
  end

  def self.session_details(session)
    decision = session.decisions.find_by(account_id: session.account_id, conversation_id: session.subject_id, anchor_message_id: session.result_id)
    details = decision ? decision.technical_details : { 'credits_consumed' => session.credits_consumed }
    details.merge({ 'model' => session.llm_model }.compact)
  end

  def self.value(details, field, applicable)
    return { status: applicable ? 'not_recorded' : 'not_applicable' } unless details.key?(field) && !details[field].nil?

    { status: 'recorded', value: details[field] }
  end
end
