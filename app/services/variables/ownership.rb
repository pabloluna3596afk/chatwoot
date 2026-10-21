class Variables::Ownership
  def self.for(definition)
    return 'formula' if definition.formula?

    calendar_types = Calendar::AppointmentAttributes::Definitions::TYPES
    return unless definition.contact_attribute? && calendar_types[definition.attribute_key] == definition.attribute_display_type
    return unless Calendar::AppointmentAttributes::Definitions.enabled_keys(definition.account).include?(definition.attribute_key)

    'calendar'
  end
end
