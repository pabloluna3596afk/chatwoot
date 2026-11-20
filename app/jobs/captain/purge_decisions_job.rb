# Community edition has no Captain decision model.
class Captain::PurgeDecisionsJob < ApplicationJob
  queue_as :purgable

  def perform; end
end

Captain::PurgeDecisionsJob.prepend_mod_with('Captain::PurgeDecisionsJob')
