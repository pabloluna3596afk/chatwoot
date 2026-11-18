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
end
