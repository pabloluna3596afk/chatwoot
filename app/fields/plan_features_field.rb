require 'administrate/field/base'

class PlanFeaturesField < Administrate::Field::Base
  def self.permitted_attribute(attribute, _options = nil)
    { attribute => [] }
  end
end
