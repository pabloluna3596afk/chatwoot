require 'rails_helper'

RSpec.describe Whatsapp::Flows::SendFlowService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:flow) { create(:whatsapp_flow, account: account) }
  let(:service) { described_class.new(conversation: conversation, sender: agent, params: { 'whatsapp_flow_id' => flow.id }) }

  before do
    flow.definition['screens'][0]['blocks'][0]['save_to'] = { 'target' => 'contact.name' }
    flow.save!
    WhatsappFlowPublication.create!(whatsapp_flow: flow, account: account,
                                    waba_id: channel.provider_config['business_account_id'], status: 'published',
                                    meta_flow_id: '1234567', published_at: Time.current)
    allow(conversation).to receive(:can_reply?).and_return(true)
  end

  it 'creates a normal agent message and freezes the mapping' do
    message = service.perform
    flow.update!(definition: flow.definition.deep_merge('screens' => []))
    expect(message).to be_outgoing
    expect(message.sender).to eq(agent)
    expect(message.additional_attributes.dig('whatsapp_flow', 'fields', 0, 'save_to', 'target')).to eq('contact.name')
  end

  it 'uses Cloud v22.0, one interactive request and a signed token' do
    message = service.perform
    url = "https://graph.facebook.com/v22.0/#{channel.provider_config['phone_number_id']}/messages"
    stub_request(:post, url).to_return(status: 200, body: { messages: [{ id: 'wamid.sent' }] }.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
    provider = Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel)
    expect(provider.send_message('593991234567', message)).to eq('wamid.sent')
    expect(WebMock).to(have_requested(:post, url).with do |request|
      payload = JSON.parse(request.body)
      parameters = payload.dig('interactive', 'action', 'parameters')
      payload['to'] == '593991234567' && parameters['mode'] == 'published' && parameters['flow_token'].present?
    end.once)
  end

  it 'shows Meta errors and preserves provider response logging' do
    message = service.perform
    url = "https://graph.facebook.com/v22.0/#{channel.provider_config['phone_number_id']}/messages"
    error_body = { error: { code: 131_047, message: 'Meta refused' } }.to_json
    stub_request(:post, url).to_return(status: 400, body: error_body,
                                       headers: { 'Content-Type' => 'application/json' })
    expect(Rails.logger).to receive(:error).with(error_body)
    Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel).send_message('593991234567', message)
    expect(message.reload).to be_failed
    expect(message.external_error).to include('Meta refused')
  end

  it 'rejects closed windows, stale publications and a different WABA' do
    allow(conversation).to receive(:can_reply?).and_return(false)
    expect { service.perform }.to raise_error(described_class::Error)
    allow(conversation).to receive(:can_reply?).and_return(true)
    flow.update!(name: 'Changed')
    expect { service.perform }.to raise_error(described_class::Error)
    flow.whatsapp_flow_publications.sole.update!(published_at: Time.current, waba_id: '999')
    expect { service.perform }.to raise_error(described_class::Error)
  end
end
