class Captain::Copilot::Resources::Contacts < Captain::Copilot::Resources::BaseResource
  NAME = 'contacts'.freeze
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze
  DATE_FIELDS = %w[created_at last_activity_at].freeze
  FILTERS = Captain::Copilot::Resources::BaseResource::CONTACT_FILTERS
  GROUPS = %w[label country blocked].freeze

  def scope
    raise ArgumentError, 'You do not have permission to view contacts' unless permitted?('contact_manage')

    @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
  end

  def filter(relation, filters)
    relation = relation.where(filters.slice('country_code', 'blocked'))
    relation = relation.tagged_with(filters['labels'], any: true) if filters['labels'].present?
    if filters['search'].present?
      term = "%#{Contact.sanitize_sql_like(filters['search'])}%"
      relation = relation.where('contacts.name ILIKE :term OR contacts.email ILIKE :term OR contacts.phone_number ILIKE :term', term: term)
    end
    custom_attribute_filter(relation, filters, 'contact_attribute')
  end

  def counts_by(relation, group)
    case group
    when 'label' then label_counts(relation)
    when 'country' then column_counts(relation, Arel.sql("NULLIF(contacts.country_code, '')"))
    when 'blocked' then column_counts(relation, :blocked)
    end
  end

  private

  def permitted?(permission)
    account_user = @account.account_users.find_by(user_id: @user&.id)
    return false unless account_user
    return account_user.custom_role.permissions.include?(permission) if account_user.custom_role.present?

    account_user.administrator? || account_user.agent?
  end
end
