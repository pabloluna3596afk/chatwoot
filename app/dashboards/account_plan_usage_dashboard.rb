require 'administrate/base_dashboard'

class AccountPlanUsageDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_field: 'name'),
    plan: Field::BelongsTo.with_options(searchable: true, searchable_field: 'name'),
    period_start: Field::DateTime,
    period_end: Field::DateTime,
    responses_consumed: Field::Number,
    copilot_responses_consumed: Field::Number,
    customer_responses_consumed: Field::Number,
    documents_consumed: Field::Number,
    limit_responses: Field::Number,
    limit_documents: Field::Number,
    closed_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    account
    plan
    period_start
    period_end
    responses_consumed
    copilot_responses_consumed
    customer_responses_consumed
    documents_consumed
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    plan
    period_start
    period_end
    responses_consumed
    copilot_responses_consumed
    customer_responses_consumed
    documents_consumed
    limit_responses
    limit_documents
    closed_at
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  # NOTE: This dashboard is read-only, so we don't actually need form attributes,
  # but we'll define them anyway for completeness (they won't be used).
  FORM_ATTRIBUTES = %i[
    account
    plan
    period_start
    period_end
    responses_consumed
    documents_consumed
    limit_responses
    limit_documents
    closed_at
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  COLLECTION_FILTERS = {
    open: ->(resources) { resources.where(closed_at: nil) },
    closed: ->(resources) { resources.where.not(closed_at: nil) }
  }.freeze

  # Overwrite this method to customize how account plan usages are displayed
  # across all pages of the admin dashboard.
  def display_resource(account_plan_usage)
    "Cuenta #{account_plan_usage.account_id} - Período #{account_plan_usage.period_start.strftime('%Y-%m-%d')} a #{account_plan_usage.period_end.strftime('%Y-%m-%d')}"
  end
end