require 'rails_helper'

RSpec.describe Whatsapp::BotTemplateBlueprintService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

  it 'preserves the legacy direct submission behavior without creating a draft' do
    endpoint = "https://graph.facebook.com/v14.0/#{channel.provider_config['business_account_id']}/message_templates"
    request = stub_request(:post, endpoint).with(body: hash_including('name' => 'palu_cita_confirmacion', 'category' => 'UTILITY'))
                                           .to_return(status: 200, body: { id: 'legacy-1', status: 'PENDING' }.to_json,
                                                      headers: { 'Content-Type' => 'application/json' })
    expect { described_class.new(channel).submit('palu_cita_confirmacion') }.not_to change(WhatsappTemplateDraft, :count)
    expect(request).to have_been_requested.once
  end
end
