require 'administrate/base_dashboard'

# Administrate inspects every top-level route resource when rendering its shared
# Super Admin navigation, including this custom report route.
class AiUsageDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = { id: Field::Number }.freeze
  COLLECTION_ATTRIBUTES = %i[id].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id].freeze
  FORM_ATTRIBUTES = %i[id].freeze
end
