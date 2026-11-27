require 'rails_helper'

RSpec.describe Whatsapp::TemplateWabaSyncService do
  let(:account) { create(:account) }
  let!(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let!(:second) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let!(:other) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:endpoint) { "https://graph.facebook.com/v22.0/#{channel.provider_config['business_account_id']}/message_templates" }
  let(:service) { described_class.new(account, channel.provider_config['business_account_id']) }

  it 'updates both numbers of the same WABA from one complete remote result, including an empty result' do
    mirror = [{ 'id' => 'meta-1', 'name' => 'remote_only', 'status' => 'PENDING' }]
    stub_request(:get, endpoint).with(query: hash_including('limit' => '100')).to_return(
      status: 200, body: { data: mirror }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    service.perform
    expect(channel.reload.message_templates).to eq(mirror)
    expect(second.reload.message_templates).to eq(mirror)
    expect(other.reload.message_templates).not_to eq(mirror)
    stub_request(:get, endpoint).with(query: hash_including('limit' => '100')).to_return(
      status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    service.perform
    expect(channel.reload.message_templates).to eq([])
    expect(second.reload.message_templates).to eq([])
  end

  it 'automatically links a compatible approved Citas draft after updating the WABA mirror' do
    account.update!(locale: 'es')
    draft = create(:whatsapp_template_draft, account: account, preferred_channel: channel,
                                             waba_id: channel.provider_config['business_account_id'])
    definition = Calendar::TemplateDefinitions.definition('confirmation', 'es')
    mirror = [{ 'id' => 'meta-confirmation', 'name' => draft.name, 'language' => 'es', 'status' => 'APPROVED',
                'category' => 'UTILITY', 'parameter_format' => 'NAMED',
                'components' => [{ 'type' => 'BODY', 'text' => definition[:body] },
                                 { 'type' => 'BUTTONS', 'buttons' => definition[:buttons].map do |text|
                                   { 'type' => 'QUICK_REPLY', 'text' => text }
                                 end }] }]
    resource = Calendar::TemplateResources.new(account: account, function: 'confirmation', language: 'es', channel: channel)
                                          .prepare!(template_name: draft.name, draft: draft)
    draft.submissions.create!(account: account, revision: 0, waba_id: draft.waba_id, name: draft.name, language: 'es',
                              snapshot: { 'payload' => {} }, payload_digest: 'digest', status: 'submitted',
                              remote_id: 'meta-confirmation', remote_status: 'APPROVED')
    stub_request(:get, endpoint).with(query: hash_including('limit' => '100')).to_return(
      status: 200, body: { data: mirror }.to_json, headers: { 'Content-Type' => 'application/json' }
    )

    service.perform

    expect(resource.reload).to have_attributes(status: 'linked', remote_template_id: 'meta-confirmation')
    expect(Calendar::TemplateDrafts::Status.new(account: account).perform.dig('results', 'confirmation', 'aggregate_state')).to eq('usable')
  end

  it 'does not replace any channel cache if a later page fails' do
    previous = channel.message_templates
    stub_request(:get, endpoint).with(query: hash_excluding('after')).to_return(
      status: 200, body: { data: [{ id: 'partial' }], paging: { next: 'next-page', cursors: { after: 'page2' } } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    stub_request(:get, endpoint).with(query: hash_including('after' => 'page2')).to_return(status: 500, body: '{}',
                                                                                           headers: { 'Content-Type' => 'application/json' })
    expect { service.perform }.to raise_error(Whatsapp::TemplateManagementService::Error)
    expect(channel.reload.message_templates).to eq(previous)
    expect(second.reload.message_templates).to eq(previous)
  end
end
