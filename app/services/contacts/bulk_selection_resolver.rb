class Contacts::BulkSelectionResolver
  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params.deep_symbolize_keys
  end

  def contact_ids
    return explicit_ids unless select_all?

    scope.pluck(:id)
  end

  private

  def select_all?
    ActiveModel::Type::Boolean.new.cast(@params[:select_all])
  end

  def explicit_ids
    Array(@params[:ids]).map { |id| id.to_i }.reject(&:zero?).uniq
  end

  def scope
    if filter_payload?
      Contacts::FilterService.new(@account, @user, filter_params).perform[:contacts]
    elsif @params[:label].present?
      resolved_contacts.tagged_with(@params[:label], any: true)
    elsif @params[:search].present?
      search_contacts
    elsif ActiveModel::Type::Boolean.new.cast(@params[:active])
      resolved_contacts.where(id: online_contact_ids)
    else
      resolved_contacts
    end
  end

  def filter_payload?
    payload = @params[:payload]
    payload.present? && Array(payload).any?
  end

  def filter_params
    { payload: @params[:payload] }.with_indifferent_access
  end

  def search_contacts
    term = "%#{@params[:search].to_s.strip}%"
    resolved_contacts.where(
      "name ILIKE :search OR email ILIKE :search OR phone_number ILIKE :search OR contacts.identifier ILIKE :search OR contacts.document_number ILIKE :search OR additional_attributes->>'company_name' ILIKE :search",
      search: term
    )
  end

  def resolved_contacts
    @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
  end

  def online_contact_ids
    ::OnlineStatusTracker.get_available_contact_ids(@account.id)
  end
end
