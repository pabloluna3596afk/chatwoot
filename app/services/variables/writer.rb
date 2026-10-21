class Variables::Writer
  def initialize(account:)
    @account = account
  end

  def target(path, context:)
    descriptors.find do |entry|
      entry[:legacyPaths].include?(path) && entry[:writable] && entry[:managedBy].nil? && entry[:writeContexts].include?(context)
    end
  end

  def attributes(record:, target:, value:, context:)
    descriptor = self.target(target, context: context)
    raise ActionController::ParameterMissing, "Unwritable variable: #{target}" unless descriptor

    scope = descriptor[:reference][:scope]
    raise ActionController::ParameterMissing, 'Invalid variable scope' unless record.class.name.underscore == scope

    if descriptor[:reference][:kind] == 'custom_attribute'
      { custom_attributes: patch(scope: scope, current: record.custom_attributes, values: { descriptor[:key] => value }) }
    elsif %w[contact.company_name contact.city].include?(target)
      { additional_attributes: record.additional_attributes.merge(target.delete_prefix('contact.') => value) }
    else
      { (target == 'contact.phone' ? 'phone_number' : target.delete_prefix('contact.')) => value }
    end
  end

  # API JSON and imports accept keys without definitions; imports report them to the user.
  # a defined managed variable can never be changed or removed through this entry point.
  def patch(scope:, values:, current: {}, replace: false)
    unless values.is_a?(Hash) || values.is_a?(ActionController::Parameters)
      raise ActionController::ParameterMissing, 'custom_attributes must be an object'
    end

    values = values.to_unsafe_h if values.is_a?(ActionController::Parameters)
    values = values.stringify_keys
    validate_keys!(scope: scope, keys: values.keys)
    if replace
      removed = current.keys - values.keys
      validate_keys!(scope: scope, keys: removed)
      values
    else
      current.merge(values)
    end
  end

  def remove(scope:, current:, keys:)
    validate_keys!(scope: scope, keys: Array.wrap(keys))
    current.except(*Array.wrap(keys))
  end

  def validate_keys!(scope:, keys:)
    managed = descriptors.select { |entry| entry[:group] == scope && entry[:managedBy] }.pluck(:key)
    blocked = keys & managed
    raise ActionController::ParameterMissing, "Read-only variables: #{blocked.join(', ')}" if blocked.any?
  end

  private

  def descriptors
    @descriptors ||= Variables::Catalog.new(account: @account, surface: 'flow').as_json.fetch(:variables)
  end
end
