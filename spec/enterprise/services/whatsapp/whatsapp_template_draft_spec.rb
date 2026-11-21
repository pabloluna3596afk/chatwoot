require 'rails_helper'

RSpec.describe WhatsappTemplateDraft do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              message_templates: [{ 'name' => 'remote_marketing', 'language' => 'es', 'status' => 'APPROVED',
                                                    'category' => 'MARKETING',
                                                    'components' => [{ 'type' => 'BODY', 'text' => 'Promoción.' }] }])
  end
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'excludes drafts and keeps remote marketing unavailable even when approved' do
    draft = create(:whatsapp_template_draft, account: account, preferred_channel: channel, waba_id: channel.provider_config['business_account_id'])
    assistant.config = assistant.config.merge('messaging' => {
                                                'version' => 2, 'revision' => 0,
                                                'inboxes' => [{ 'inbox_id' => channel.inbox.id, 'enabled' => true, 'mode' => 'auto' }]
                                              })
    items = Captain::Messaging::Availability.new(assistant, channel.inbox).templates
    expect(items.map { |item| item.resource['name'] }).not_to include(draft.name)
    marketing = items.find { |item| item.resource['name'] == 'remote_marketing' }
    expect(marketing.state).to eq('marketing_off')
  end
end
