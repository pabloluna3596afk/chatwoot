require 'administrate/field/base'

class PlanLimitsField < Administrate::Field::Base
  def self.permitted_attribute(attribute, _options = nil)
    { attribute => Plan::LIMITS.map { |limit| limit[:key].to_s } }
  end
end
