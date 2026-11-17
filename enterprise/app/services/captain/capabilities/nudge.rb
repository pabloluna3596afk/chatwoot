class Captain::Capabilities::Nudge < Captain::Capabilities::Base
  def call
    return result('off', 'disabled') unless assistant.followup.inactivity_enabled? && assistant.followup.max_nudges.to_i.positive?

    result('ready')
  end
end
