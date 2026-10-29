require 'administrate/base_dashboard'

class AiModelPriceDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    model: Field::String,
    input_per_million: Field::Number,
    cached_input_per_million: Field::Number,
    output_per_million: Field::Number,
    effective_from: Field::DateTime,
    active: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[model input_per_million cached_input_per_million output_per_million effective_from active].freeze
  SHOW_PAGE_ATTRIBUTES = COLLECTION_ATTRIBUTES
  FORM_ATTRIBUTES = %i[model input_per_million cached_input_per_million output_per_million effective_from active].freeze

  def display_resource(price)
    "#{price.model} · #{price.effective_from.strftime('%Y-%m-%d')}"
  end
end
