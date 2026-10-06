# Publishes a flow to every WhatsApp Cloud WABA of the account (or only `waba_id`, for "Reintentar"). Each WABA is
# independent: one failing does not stop the others, and every result lands in its WhatsappFlowPublication, which the
# dashboard polls. Network trouble, 5xx and rate limits retry the whole run a few times (safe: the services are
# idempotent and a published WABA is a no-op); validation errors are stored and never retried.
class Whatsapp::PublishFlowToMetaJob < ApplicationJob
  queue_as :default

  class RetryableError < StandardError; end

  retry_on RetryableError, wait: ->(executions) { [5, 30, 120][executions - 1] || 120 }, attempts: 3

  def perform(flow_id, account_id, waba_id = nil)
    account = Account.find(account_id)
    flow = account.whatsapp_flows.find(flow_id)
    channels = Whatsapp::Flows::CloudChannels.for(account)
    channels = channels.select { |channel| channel.provider_config['business_account_id'] == waba_id } if waba_id.present?

    results = channels.map { |channel| Whatsapp::Flows::PublishToMetaService.new(flow, channel).perform }
    raise RetryableError, "flow #{flow.id}: Meta unreachable for some WABAs" if results.any? { |result| result[:retryable] }
  end
end
