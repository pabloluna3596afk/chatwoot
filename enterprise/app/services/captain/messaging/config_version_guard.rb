class Captain::Messaging::ConfigVersionGuard
  def initialize(assistant)
    @assistant = assistant
  end

  def check(config)
    return true unless messaging_supplied?(config)
    return true unless versioned_config?

    apply_version_check(config)
  end

  private

  def remove_unchanged(config, incoming, saved)
    return false unless incoming == saved

    config.delete(:messaging)
    config.delete('messaging')
    true
  end

  def messaging_supplied?(config)
    config&.key?(:messaging) || config&.key?('messaging')
  end

  def versioned_config?
    saved = @assistant.config['messaging']
    saved.is_a?(Hash) && saved['version'] == 2
  end

  def apply_version_check(config)
    incoming = plain_hash(config[:messaging] || config['messaging'])
    saved = @assistant.config['messaging']
    return remove_unchanged(config, incoming, saved) if incoming == saved
    return advance_revision(config, incoming, saved) if current_revision?(incoming, saved)

    false
  end

  # Request params arrive as ActionController::Parameters, which Rails 7.2 no longer treats as a Hash or
  # compares equal to one, so an untouched block sent back by a settings form looked like a conflict.
  def plain_hash(value)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value.respond_to?(:deep_stringify_keys) ? value.deep_stringify_keys : value
  end

  def current_revision?(incoming, saved)
    incoming.is_a?(Hash) && incoming['version'] == 2 && incoming['revision'] == saved['revision']
  end

  def advance_revision(config, incoming, saved)
    incoming['revision'] = saved['revision'].to_i + 1
    config[config.key?(:messaging) ? :messaging : 'messaging'] = incoming
    true
  end
end
