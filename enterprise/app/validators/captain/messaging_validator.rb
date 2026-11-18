# Validates assistant.config['messaging']: which Flows and templates Captain may send, per inbox.
# Everything is opt-in, per inbox: no block, or an inbox without `enabled: true`, means Captain sends nothing there.
# This only checks what is stored; the sending itself revalidates the current state of every resource when it happens.
class Captain::MessagingValidator < ActiveModel::Validator
  MAX_INBOXES = 20
  MAX_RESOURCES = 50
  MAX_PURPOSE_LENGTH = 300
  MAX_TEXT_LENGTH = 512
  ROOT_KEYS = %w[version revision inboxes].freeze
  INBOX_KEYS = %w[inbox_id enabled mode flows templates excluded included_marketing notes params reviewed].freeze
  FLOW_KEYS = %w[flow_id purpose].freeze
  TEMPLATE_KEYS = %w[name language purpose processed_params].freeze

  def validate(record)
    raw = record.config['messaging']
    return if raw.nil?
    return error(record, 'must be an object') unless raw.is_a?(Hash)

    unknown_keys(record, 'messaging', raw, ROOT_KEYS)
    error(record, 'version must be 2') if raw.key?('version') && raw['version'] != 2
    error(record, 'revision must be a non-negative integer') if raw.key?('revision') && (!raw['revision'].is_a?(Integer) || raw['revision'].negative?)
    validate_inboxes(record, raw['inboxes'])
    return unless Array(raw['inboxes']).any? { |entry| entry.is_a?(Hash) && entry.fetch('mode', 'list') == 'auto' }

    error(record, 'auto mode requires version 2 and revision') unless raw['version'] == 2 && raw['revision'].is_a?(Integer)
  end

  private

  def error(record, message)
    record.errors.add(:config, "messaging #{message}")
  end

  def unknown_keys(record, where, hash, allowed)
    extra = hash.keys.map(&:to_s) - allowed
    error(record, "#{where} has unknown keys: #{extra.join(', ')}") if extra.any?
  end

  def validate_inboxes(record, inboxes)
    return error(record, 'inboxes must be a list') unless inboxes.is_a?(Array)
    return error(record, "inboxes cannot have more than #{MAX_INBOXES} entries") if inboxes.size > MAX_INBOXES

    ids = inboxes.map { |entry| entry.is_a?(Hash) ? entry['inbox_id'] : nil }
    error(record, 'inboxes cannot repeat an inbox') if ids.compact.uniq.size != ids.compact.size
    inboxes.each { |entry| validate_inbox_entry(record, entry) }
  end

  def validate_inbox_entry(record, entry)
    return error(record, 'every inbox entry must be an object') unless entry.is_a?(Hash)

    unknown_keys(record, 'an inbox entry', entry, INBOX_KEYS)
    validate_inbox(record, entry['inbox_id'])
    error(record, 'inbox enabled must be true or false') unless [true, false].include?(entry['enabled'])
    mode = entry.fetch('mode', 'list')
    error(record, 'inbox mode must be auto or list') unless %w[auto list].include?(mode)
    if mode == 'auto'
      %w[flows templates].each { |key| error(record, "#{key} are not allowed in auto mode") if entry.key?(key) }
      validate_auto_entry(record, entry)
    else
      %w[excluded included_marketing notes params reviewed].each do |key|
        error(record, "#{key} are not allowed in list mode") if entry.key?(key)
      end
      validate_flows(record, entry['flows'] || [], record.account)
      validate_templates(record, entry['templates'] || [])
    end
  end

  def validate_auto_entry(record, entry)
    validate_scoped_keys(record, entry['excluded'], %w[templates flows], 'excluded') if entry.key?('excluded')
    validate_scoped_keys(record, entry['included_marketing'], nil, 'included_marketing') if entry.key?('included_marketing')
    validate_notes(record, entry['notes']) if entry.key?('notes')
    validate_params(record, entry['params']) if entry.key?('params')
    validate_reviewed(record, entry['reviewed']) if entry.key?('reviewed')
  end

  def validate_scoped_keys(record, value, kinds, label)
    lists = if kinds
              return error(record, "#{label} must be an object") unless value.is_a?(Hash)

              unknown_keys(record, label, value, kinds)
              kinds.index_with { |kind| value.fetch(kind, []) }
            else
              { label => value }
            end
    lists.each do |kind, list|
      next error(record, "#{label} #{kind} must be a list") unless list.is_a?(Array)
      next error(record, "#{label} #{kind} cannot have more than #{MAX_RESOURCES} entries") if list.size > MAX_RESOURCES

      error(record, "#{label} #{kind} cannot repeat entries") unless list.uniq.size == list.size
      list.each do |item|
        pattern = kind == 'flows' ? /\A\d+:\d+\z/ : /\A\d+:[^|]+\|[^|]+\z/
        valid = item.is_a?(String) && item.match?(pattern)
        error(record, "#{label} #{kind} entries must include a WABA-scoped resource identity") unless valid
      end
    end
  end

  def validate_notes(record, notes)
    return error(record, 'notes must be an object') unless notes.is_a?(Hash)

    notes.each do |key, value|
      valid_key = key.to_s.match?(/\A(?:template:\d+:[^|]+\|[^|]+|flow:\d+:\d+)\z/)
      error(record, "note key #{key.inspect} is invalid") unless valid_key
      unless value.is_a?(String) && value.length <= MAX_PURPOSE_LENGTH
        error(record,
              "note #{key.inspect} must be a text up to #{MAX_PURPOSE_LENGTH} characters")
      end
    end
  end

  def validate_params(record, params)
    return error(record, 'params must be an object') unless params.is_a?(Hash)

    params.each do |key, values|
      match = /\A\d+:([^|]+)\|([^|]+)\z/.match(key.to_s)
      unless match && values.is_a?(Hash)
        error(record, "params key #{key.inspect} must include a WABA-scoped template identity")
        next
      end
      reference = { 'name' => match[1], 'language' => match[2], 'processed_params' => values }
      Captain::TemplateReference.errors(reference, record.account).each do |message|
        error(record, "params #{key} #{message}")
      end
    end
  end

  def validate_reviewed(record, reviewed)
    return error(record, 'reviewed must be an object') unless reviewed.is_a?(Hash)

    unknown_keys(record, 'reviewed', reviewed, %w[templates flows])
    %w[templates flows].each do |kind|
      resources = reviewed.fetch(kind, {})
      unless resources.is_a?(Hash)
        error(record, "reviewed #{kind} must be an object")
        next
      end
      resources.each do |key, value|
        valid_key = kind == 'templates' ? key.to_s.match?(/\A\d+:[^|]+\|[^|]+\z/) : key.to_s.match?(/\A\d+:\d+\z/)
        valid_value = kind == 'templates' ? value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/) : value.is_a?(Integer) && value.positive?
        error(record, "reviewed #{kind} entry #{key.inspect} is invalid") unless valid_key && valid_value
      end
    end
  end

  def validate_inbox(record, inbox_id)
    inbox = inbox_id.is_a?(Integer) ? record.account.inboxes.find_by(id: inbox_id) : nil
    return error(record, 'inbox_id must be an inbox of this account') unless inbox
    return if inbox.channel_type == 'Channel::Whatsapp'

    error(record, "inbox #{inbox_id} must be a WhatsApp inbox")
  end

  # The entries of a list that are objects; anything else, or a list that is too long, is reported.
  def object_entries(record, name, list)
    return error(record, "#{name}s must be a list") unless list.is_a?(Array)
    return error(record, "#{name}s cannot have more than #{MAX_RESOURCES} entries") if list.size > MAX_RESOURCES

    entries = list.select { |item| item.is_a?(Hash) }
    error(record, "every #{name} must be an object") if entries.size != list.size
    entries
  end

  def validate_flows(record, flows, account)
    entries = object_entries(record, 'flow', flows)
    return unless entries.is_a?(Array)

    ids = entries.pluck('flow_id')
    error(record, 'flows cannot repeat a flow') if ids.uniq.size != ids.size
    entries.each { |flow| validate_flow(record, flow, account) }
  end

  def validate_flow(record, flow, account)
    unknown_keys(record, 'a flow', flow, FLOW_KEYS)
    id = flow['flow_id']
    valid = id.is_a?(Integer) && account.whatsapp_flows.exists?(id: id)
    error(record, "flow_id #{id.inspect} must be a Flow of this account") unless valid
    validate_purpose(record, flow['purpose'])
  end

  def validate_templates(record, templates)
    entries = object_entries(record, 'template', templates)
    return unless entries.is_a?(Array)

    keys = entries.map { |template| [template['name'], template['language']] }
    error(record, 'templates cannot repeat a template') if keys.uniq.size != keys.size
    entries.each { |template| validate_template(record, template) }
  end

  def validate_template(record, template)
    unknown_keys(record, 'a template', template, TEMPLATE_KEYS)
    %w[name language].each do |key|
      value = template[key]
      valid = value.is_a?(String) && value.present? && value.length <= MAX_TEXT_LENGTH
      error(record, "template #{key} must be a text up to #{MAX_TEXT_LENGTH} characters") unless valid
    end
    validate_purpose(record, template['purpose'])
    validate_variables(record, template)
  end

  # What fills each variable of the template (see Captain::TemplateReference). Optional while it is being set up, but a
  # template whose variables are not all filled cannot be sent.
  def validate_variables(record, template)
    return unless template.key?('processed_params')

    reference = template.slice('name', 'language', 'processed_params')
    Captain::TemplateReference.errors(reference, record.account).each do |message|
      error(record, "template #{template['name']} #{message}")
    end
  end

  def validate_purpose(record, purpose)
    return if purpose.nil? || (purpose.is_a?(String) && purpose.length <= MAX_PURPOSE_LENGTH)

    error(record, "purpose must be a text up to #{MAX_PURPOSE_LENGTH} characters")
  end
end
