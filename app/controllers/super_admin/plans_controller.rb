class SuperAdmin::PlansController < SuperAdmin::ApplicationController
  private

  def resource_params
    attributes = super
    # Checkbox forms submit one empty sentinel so every feature can be cleared.
    attributes[:feature_keys] = attributes[:feature_keys].reject { |key| key == '' } if attributes.key?(:feature_keys)
    attributes
  end
end
