require 'administrate/base_dashboard'

class ExtraPackDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    bucket: Field::Select.with_options(collection: ExtraPack::BUCKETS),
    units: Field::Number,
    price_usd: Field::Number.with_options(decimals: 2),
    active: Field::Boolean,
    display_order: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze
  COLLECTION_ATTRIBUTES = %i[bucket units price_usd active display_order].freeze
  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze
  FORM_ATTRIBUTES = %i[bucket units price_usd active display_order].freeze
  COLLECTION_FILTERS = {}.freeze

  def display_resource(pack)
    "#{pack.bucket}: #{pack.units}"
  end
end
