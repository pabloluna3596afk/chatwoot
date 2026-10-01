# Runs every minute (config/schedule.yml). The community edition has nothing to do; the enterprise module nudges
# and closes the inactive conversations Captain handles and sends the re-engagement templates.
class Conversations::CaptainFollowupJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform; end
end

Conversations::CaptainFollowupJob.prepend_mod_with('Conversations::CaptainFollowupJob')
