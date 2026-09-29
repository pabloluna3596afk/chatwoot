require 'administrate/base_dashboard'

class PlanDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String.with_options(searchable: true),
    slug: Field::String.with_options(searchable: true),
    description: Field::String,
    monthly_messages: Field::Number,
    storage_mb: Field::Number,
    max_documents: Field::Number,
    max_captain_assistants: Field::Number,
    max_human_agents: Field::Number,
    max_inboxes: Field::Number,
    max_emails_per_day: Field::Number,
    price_monthly: Field::Number.with_options(decimals: 2),
    price_yearly: Field::Number.with_options(decimals: 2),
    trial_days: Field::Number,
    trial_messages: Field::Number,
    is_default_trial: Field::Boolean,
    addon_agent_price: Field::Number.with_options(decimals: 2),
    addon_bot_price: Field::Number.with_options(decimals: 2),
    credit_unit_price: Field::Number.with_options(decimals: 4),
    is_active: Field::Boolean,
    is_public: Field::Boolean,
    display_order: Field::Number,
    accounts: Field::HasMany,
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
    name
    price_monthly
    monthly_messages
    max_human_agents
    max_inboxes
    is_active
    is_public
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    slug
    description
    monthly_messages
    storage_mb
    max_documents
    max_captain_assistants
    max_human_agents
    max_inboxes
    max_emails_per_day
    price_monthly
    price_yearly
    trial_days
    trial_messages
    is_default_trial
    addon_agent_price
    addon_bot_price
    credit_unit_price
    is_active
    is_public
    display_order
    accounts
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    name
    slug
    description
    monthly_messages
    storage_mb
    max_documents
    max_captain_assistants
    max_human_agents
    max_inboxes
    max_emails_per_day
    price_monthly
    price_yearly
    trial_days
    trial_messages
    is_default_trial
    addon_agent_price
    addon_bot_price
    credit_unit_price
    is_active
    is_public
    display_order
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  COLLECTION_FILTERS = {
    active: ->(resources) { resources.where(is_active: true) },
    public: ->(resources) { resources.where(is_public: true) }
  }.freeze

  # Overwrite this method to customize how plans are displayed
  # across all pages of the admin dashboard.
  def display_resource(plan)
    "#{plan.name} (#{plan.slug})"
  end
end
