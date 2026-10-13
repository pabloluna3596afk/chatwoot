class Calendar::AppointmentAttributes::Provisioner
  TYPES = Calendar::AppointmentAttributes::Definitions::TYPES

  def initialize(account:)
    @account = account
  end

  def status
    @account.appointment_attributes || { 'keys' => nil, 'enabled_keys' => [], 'results' => {} }
  end

  def perform(keys:)
    backfill = false
    @account.with_lock do
      results = keys.index_with { |key| provision(key) }
      enabled = keys.reject { |key| results[key]['status'] == 'conflict' }
      newly_enabled = enabled - Calendar::AppointmentAttributes::Definitions.enabled_keys(@account)
      backfill = newly_enabled.any? || results.values.any? { |result| result['status'] == 'created' }
      @account.update!(appointment_attributes: { 'keys' => keys, 'enabled_keys' => enabled, 'results' => results })
    end
    Calendar::AppointmentAttributes::BackfillJob.perform_later(@account.id) if backfill
    status
  end

  private

  def provision(key)
    type = TYPES.fetch(key)
    definition = @account.custom_attribute_definitions.contact_attribute.find_or_create_by!(attribute_key: key) do |record|
      record.attribute_display_type = type
      record.attribute_display_name = I18n.t("integration_apps.calendars.appointment_attributes.#{key}", locale: @account.locale)
      record.category = Calendar::AppointmentAttributes::Definitions::CATEGORY
    end
    status = definition.previously_new_record? ? 'created' : 'reused'
    status = 'conflict' unless definition.attribute_display_type == type
    { 'status' => status, 'expected_type' => type, 'actual_type' => definition.attribute_display_type }
  end
end
