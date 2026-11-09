require 'administrate/base_dashboard'

class AccountExtraBalanceDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    bucket: Field::Select.with_options(collection: ExtraPack::BUCKETS),
    units_total: Field::Number,
    units_remaining: Field::Number,
    expires_at: Field::DateTime,
    source: Field::String,
    extra_pack: Field::BelongsTo,
    external_reference: Field::String,
    created_at: Field::DateTime
  }.freeze
  COLLECTION_ATTRIBUTES = %i[account bucket units_total units_remaining expires_at source].freeze
  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze
  FORM_ATTRIBUTES = %i[account bucket units_total].freeze
  COLLECTION_FILTERS = {}.freeze

  def display_resource(balance)
    "#{balance.bucket}: #{balance.units_remaining}"
  end
end
