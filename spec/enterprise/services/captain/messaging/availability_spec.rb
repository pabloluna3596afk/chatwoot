require 'rails_helper'

RSpec.describe Captain::Messaging::Availability do
  let(:account) { create(:account) }
  let(:template) do
    { 'name' => 'order_ready', 'language' => 'es', 'category' => 'UTILITY', 'status' => 'APPROVED',
      'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}' }] }
  end
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false,
                              validate_provider_config: false, message_templates: [template],
                              provider_config: { 'business_account_id' => '123' })
  end
  let(:inbox) { channel.inbox }
  let(:assistant) { create(:captain_assistant, account: account) }

  def enable_auto(reviewed: {})
    assistant.config = assistant.config.merge('messaging' => {
                                                'version' => 2, 'revision' => 0,
                                                'inboxes' => [{ 'inbox_id' => inbox.id, 'enabled' => true, 'mode' => 'auto', 'reviewed' => reviewed }]
                                              })
  end

  it 'marks an unreviewed approved utility template as new' do
    enable_auto

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('new')
  end

  it 'keeps authentication unavailable even if a reviewed fingerprint exists' do
    auth = template.merge('category' => 'AUTHENTICATION')
    channel.update!(message_templates: [auth])
    fingerprint = Digest::SHA256.hexdigest({ category: 'AUTHENTICATION', components: auth['components'],
                                             parameter_format: nil }.to_json)
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => fingerprint }, 'flows' => {} })

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('authentication')
  end

  it 'requires an explicit review for new links in auto mode' do
    linked = template.merge('components' => [{ 'type' => 'BODY', 'text' => 'Open' },
                                             { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.com' }] }])
    channel.update!(message_templates: [linked])
    enable_auto

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('needs_review')
  end

  it 'gives exclusion precedence over marketing inclusion' do
    marketing = template.merge('category' => 'MARKETING')
    channel.update!(message_templates: [marketing])
    fingerprint = Digest::SHA256.hexdigest({ category: marketing['category'], components: marketing['components'],
                                             parameter_format: nil }.to_json)
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => fingerprint }, 'flows' => {} })
    entry = assistant.config.dig('messaging', 'inboxes').first
    entry['included_marketing'] = ['123:order_ready|es']
    entry['excluded'] = { 'templates' => ['123:order_ready|es'], 'flows' => [] }

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('excluded')
  end

  it 'keeps a reviewed authentication template unavailable even when explicitly allowed' do
    auth = template.merge('category' => 'AUTHENTICATION')
    channel.update!(message_templates: [auth])
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => 'a' * 64 }, 'flows' => {} })

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('authentication')
  end

  it 'marks a template changed after its category changes' do
    old_fingerprint = Digest::SHA256.hexdigest({ category: template['category'], components: template['components'],
                                                 parameter_format: nil }.to_json)
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => old_fingerprint }, 'flows' => {} })
    channel.update!(message_templates: [template.merge('category' => 'MARKETING')])

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('changed')
  end

  it 'does not reuse a reviewed template from another WABA' do
    channel.update!(provider_config: { 'business_account_id' => '456' })
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => 'a' * 64 }, 'flows' => {} })

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('new')
  end

  it 'marks a Flow published only to a different WABA as unavailable here' do
    flow = create(:whatsapp_flow, account: account)
    flow.whatsapp_flow_publications.create!(account: account, waba_id: '456', status: 'published', published_version: 1)
    enable_auto(reviewed: { 'templates' => {}, 'flows' => { "123:#{flow.id}" => 1 } })

    expect(described_class.new(assistant, inbox).flows.find { |item| item.resource['id'] == flow.id }.state)
      .to eq('not_published_here')
  end

  it 'marks an approved positional variable as missing data and returns explicit empty params' do
    positional = template.merge('components' => [{ 'type' => 'BODY', 'text' => 'Order {{1}}' }])
    channel.update!(message_templates: [positional])
    fingerprint = Digest::SHA256.hexdigest({ category: positional['category'], components: positional['components'],
                                             parameter_format: nil }.to_json)
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => fingerprint }, 'flows' => {} })

    item = described_class.new(assistant, inbox).templates.first

    expect(item.state).to eq('needs_data')
    expect(item.processed_params).to eq('body' => {}, 'header' => {})
  end

  it 'blocks every template when Meta health is RED' do
    channel.update!(phone_number_health: { 'quality_rating' => 'RED' })
    fingerprint = Digest::SHA256.hexdigest({ category: template['category'], components: template['components'],
                                             parameter_format: nil }.to_json)
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => fingerprint }, 'flows' => {} })

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('unavailable')
  end

  it 'allows a reviewed template when Meta health data is absent' do
    unparameterized = template.merge('components' => [{ 'type' => 'BODY', 'text' => 'Ready' }])
    channel.update!(message_templates: [unparameterized], phone_number_health: nil)
    fingerprint = Digest::SHA256.hexdigest({ category: unparameterized['category'],
                                             components: unparameterized['components'], parameter_format: nil }.to_json)
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => fingerprint }, 'flows' => {} })

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('available')
  end

  it 'rejects a template paused in Meta after its review' do
    fingerprint = Digest::SHA256.hexdigest({ category: template['category'], components: template['components'],
                                             parameter_format: nil }.to_json)
    enable_auto(reviewed: { 'templates' => { '123:order_ready|es' => fingerprint }, 'flows' => {} })
    channel.update!(message_templates: [template.merge('status' => 'PAUSED')])

    expect(described_class.new(assistant, inbox).templates.first.state).to eq('rejected')
  end

  it 'snapshots an inbox once and returns its activation notice count' do
    assistant.update!(config: { 'messaging' => { 'version' => 2, 'revision' => 0,
                                                 'inboxes' => [{ 'inbox_id' => inbox.id, 'enabled' => true, 'mode' => 'auto' }] } })

    notices = Captain::Messaging::Snapshotter.perform!(assistant)

    expect(notices).to contain_exactly(hash_including(inbox_id: inbox.id, count: 1))
    expect(notices.first[:message]).to be_present
    expect(assistant.reload.messaging.entry_for(inbox.id).dig('reviewed', 'templates')).to include('123:order_ready|es')
    expect(Captain::Messaging::Snapshotter.perform!(assistant)).to be_nil
  end
end
