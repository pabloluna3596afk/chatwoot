# The WhatsApp Cloud channels a flow is sent to: one per WABA, because two numbers on the same WABA share the same Meta
# flow and status. 360dialog (non-Cloud) channels are left out: their flows stay internal.
module Whatsapp::Flows::CloudChannels
  def self.for(account)
    account.whatsapp_channels.where(provider: 'whatsapp_cloud').order(:id)
           .select { |channel| channel.provider_config['business_account_id'].present? }
           .uniq { |channel| channel.provider_config['business_account_id'] }
  end
end
