class Variables::Catalog
  SCHEMA_VERSION = 1
  SURFACES = {
    'message' => %w[contact agent conversation inbox account date],
    'campaign' => %w[contact agent inbox account date],
    'automation' => %w[contact agent conversation inbox account date],
    'flow' => %w[contact agent conversation inbox account date flow],
    'captain' => %w[contact agent conversation inbox account date appointment assistant],
    'email' => %w[contact agent conversation inbox account message]
  }.freeze
  FIELDS = {
    'contact' => %w[id name first_name last_name email phone phone_number document_number identifier country_code city company_name
                    assigned_agent.id assigned_agent.name assigned_agent.available_name assigned_agent.email assigned_agent.first_name
                    assigned_agent.last_name],
    'agent' => %w[id name available_name email first_name last_name],
    'conversation' => %w[id display_id contact_name recent_messages],
    'inbox' => %w[id name business_name avatar_url email],
    'account' => %w[id name locale timezone],
    'date' => %w[today now tomorrow yesterday days_from_now days_ago current_year current_month current_day],
    'message' => %w[id sender_display_name text_content],
    'appointment' => %w[title date time datetime],
    'assistant' => %w[name],
    'company' => %w[id name domain description contacts_count],
    'flow' => %w[variables]
  }.freeze
  ALIASES = {
    'contact.name' => %w[nombre], 'contact.first_name' => %w[primer_nombre], 'contact.last_name' => %w[apellido],
    'contact.email' => %w[correo], 'contact.phone' => %w[telefono], 'contact.company_name' => %w[empresa],
    'contact.city' => %w[ciudad], 'contact.country_code' => %w[pais], 'contact.document_number' => %w[documento],
    'agent.name' => %w[agente], 'conversation.id' => %w[numero_conversacion], 'appointment.title' => %w[cita tema],
    'appointment.date' => %w[fecha], 'appointment.time' => %w[hora], 'appointment.datetime' => %w[fecha_hora],
    'assistant.name' => %w[asistente], 'account.name' => %w[cuenta]
  }.freeze
  WRITABLE = %w[contact.name contact.email contact.phone contact.company_name contact.city contact.document_number].freeze
  WRITE_CONTEXTS = %w[whatsapp_flow automation manual prechat].freeze
  SYSTEM_TYPES = {
    'date' => %w[date.today date.tomorrow date.yesterday date.days_from_now date.days_ago appointment.date],
    'datetime' => %w[date.now appointment.datetime],
    'number' => %w[date.current_year date.current_month date.current_day company.contacts_count],
    'list' => %w[conversation.recent_messages],
    'object' => %w[flow.variables]
  }.freeze

  def initialize(account:, surface:)
    @account = account
    @surface = surface
  end

  def as_json
    definitions = @account.custom_attribute_definitions.order(:id).to_a
    @taken_aliases = ALIASES.values.flatten
    entries = system_entries + definitions.map { |definition| attribute_entry(definition) }
    {
      schemaVersion: SCHEMA_VERSION,
      definitionsVersion: Digest::SHA256.hexdigest([@account.appointment_attributes, definitions.map(&:attributes)].to_json),
      surface: @surface,
      contexts: contexts,
      variables: entries
    }
  end

  private

  def contexts
    SURFACES.fetch(@surface)
  end

  def descriptor(scope, path, type: 'text', managed_by: nil, writable: false)
    {
      id: path, reference: { scope: scope, kind: 'system', path: path }, key: path, label: path,
      group: scope, type: type, options: [], readable: true, writable: writable,
      writeContexts: writable ? WRITE_CONTEXTS : [], requiresContext: [scope], managedBy: managed_by,
      aliases: ALIASES.fetch(path, []), legacyPaths: [path], expression: "{{ #{path} }}",
      available: contexts.include?(scope)
    }
  end

  def system_entries
    FIELDS.flat_map do |scope, fields|
      fields.map do |field|
        path = "#{scope}.#{field}"
        type = SYSTEM_TYPES.find { |_, paths| paths.include?(path) }&.first || 'text'
        descriptor(scope, path, type: type, writable: WRITABLE.include?(path))
      end
    end
  end

  def attribute_entry(definition)
    scope = definition.attribute_model.delete_suffix('_attribute')
    path = "#{scope}.custom_attribute.#{definition.attribute_key}"
    managed_by = owner(definition)
    entry = descriptor(scope, path, type: definition.attribute_display_type, managed_by: managed_by, writable: managed_by.nil?)
    entry.merge(
      id: "#{scope}.custom_attribute:#{definition.id}",
      reference: { scope: scope, kind: 'custom_attribute', definitionId: definition.id },
      key: definition.attribute_key, label: definition.attribute_display_name, options: definition.attribute_values || [],
      aliases: attribute_aliases(scope, definition.attribute_key),
      expression: "{{ #{scope}.custom_attribute['#{definition.attribute_key}'] }}"
    )
  end

  def owner(definition)
    return 'formula' if definition.formula?

    calendar_types = Calendar::AppointmentAttributes::Definitions::TYPES
    return unless definition.contact_attribute? && calendar_types[definition.attribute_key] == definition.attribute_display_type
    return unless Calendar::AppointmentAttributes::Definitions.enabled_keys(@account).include?(definition.attribute_key)

    'calendar'
  end

  def attribute_aliases(scope, key)
    name = scope == 'conversation' ? "conversacion_#{key}" : key
    return [] unless %w[contact conversation].include?(scope) && name.match?(/\A[a-z][a-z0-9_]*\z/)
    return [] if @taken_aliases.include?(name)

    @taken_aliases << name
    [name]
  end
end

Variables::Catalog.prepend_mod_with('Variables::Catalog')
