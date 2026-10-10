# Validates assistant.config['messaging']: which Flows and templates Captain may send, per inbox.
# Everything is opt-in, per inbox: no block, or an inbox without `enabled: true`, means Captain sends nothing there.
# This only checks what is stored; the sending itself revalidates the current state of every resource when it happens.
class Captain::MessagingValidator < ActiveModel::Validator
  MAX_INBOXES = 20
  MAX_RESOURCES = 50
  MAX_PURPOSE_LENGTH = 300
  MAX_TEXT_LENGTH = 512
  ROOT_KEYS = %w[inboxes].freeze
  INBOX_KEYS = %w[inbox_id enabled flows templates].freeze
  FLOW_KEYS = %w[flow_id purpose].freeze
  TEMPLATE_KEYS = %w[name language purpose].freeze

  def validate(record)
    raw = record.config['messaging']
    return if raw.nil?
    return error(record, 'must be an object') unless raw.is_a?(Hash)

    unknown_keys(record, 'messaging', raw, ROOT_KEYS)
    validate_inboxes(record, raw['inboxes'])
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
    validate_flows(record, entry['flows'] || [], record.account)
    validate_templates(record, entry['templates'] || [])
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
  end

  def validate_purpose(record, purpose)
    return if purpose.nil? || (purpose.is_a?(String) && purpose.length <= MAX_PURPOSE_LENGTH)

    error(record, "purpose must be a text up to #{MAX_PURPOSE_LENGTH} characters")
  end
end
