class Calendar::TemplateDrafts::SubmissionInput
  def initialize(account, functions, waba_ids)
    @account = account
    @functions = functions
    @waba_ids = waba_ids
  end

  def valid?
    valid_functions? && valid_waba_ids?
  end

  private

  def valid_functions?
    return false unless @functions.is_a?(Array) && @functions.present? && @functions.all?(String)
    return false unless @functions.uniq == @functions && (@functions - Calendar::TemplateDefinitions::FUNCTIONS.keys).empty?

    @functions.all? { |function| prepared_draft_exists?(function) }
  end

  def valid_waba_ids?
    return false unless @waba_ids.is_a?(Array) && @waba_ids.present? && @waba_ids.all? { |value| value.is_a?(String) && value.present? }
    return false unless @waba_ids.uniq == @waba_ids

    (@waba_ids - available_waba_ids).empty?
  end

  def available_waba_ids
    @account.whatsapp_channels.where(provider: 'whatsapp_cloud')
            .pluck(Arel.sql("provider_config ->> 'business_account_id'")).compact.uniq
  end

  def prepared_draft_exists?(function)
    draft_id = @account.calendar_template_preparation&.dig('results', function, 'draft_id')
    draft_id && @account.whatsapp_template_drafts.active.exists?(id: draft_id)
  end
end
