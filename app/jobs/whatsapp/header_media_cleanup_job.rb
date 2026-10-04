class Whatsapp::HeaderMediaCleanupJob < ApplicationJob
  queue_as :purgable

  def perform
    Whatsapp::HeaderMediaCleanupService.new.perform
  end
end
