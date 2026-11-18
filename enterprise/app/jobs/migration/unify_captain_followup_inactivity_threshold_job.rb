class Migration::UnifyCaptainFollowupInactivityThresholdJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    Captain::Assistant.find_each do |assistant|
      assistant.with_lock do
        followup = assistant.config['followup']
        next unless followup.is_a?(Hash) && followup['inactivity_enabled'] == true

        settings = Captain::FollowupSettings.new(followup)
        next unless settings.max_nudges.positive?

        next unless followup.key?('close_after_minutes')

        close_after = settings.close_after_minutes
        next unless close_after.is_a?(Integer)
        next if assistant.config['auto_resolve_after'] == close_after

        assistant.update!(config: assistant.config.merge('auto_resolve_after' => close_after))
      end
    end
  end
end
