# The community edition has no Captain outcomes to inspect.
class Captain::FailureSpikeJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform; end
end

Captain::FailureSpikeJob.prepend_mod_with('Captain::FailureSpikeJob')
