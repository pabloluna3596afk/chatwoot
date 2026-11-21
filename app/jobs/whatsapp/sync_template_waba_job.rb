class Whatsapp::SyncTemplateWabaJob < ApplicationJob
  queue_as :default

  retry_on Whatsapp::TemplateManagementService::Error, wait: :polynomially_longer, attempts: 3

  def perform(account_id, waba_id)
    Whatsapp::TemplateWabaSyncService.new(Account.find(account_id), waba_id).perform
  end
end
