require 'rails_helper'

RSpec.describe WhatsappTemplateDraft do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let!(:draft) do
    create(:whatsapp_template_draft, account: account, preferred_channel: channel, waba_id: channel.provider_config['business_account_id'],
                                     name: 'local_only', definition: { 'body' => { 'text' => 'Local draft content' } })
  end
  let(:template_params) { { 'name' => draft.name, 'language' => draft.language, 'processed_params' => {} } }

  it 'never inserts local drafts into the channel sending catalog or template processor' do
    expect(channel.reload.message_templates.pluck('name')).not_to include(draft.name)
    result = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: template_params).call
    expect(result.last).to be_nil
    expect(result.to_json).not_to include('Local draft content')
  end

  it 'does not let automation resolve a draft as an approved remote template' do
    conversation = create(:conversation, account: account, inbox: channel.inbox)
    rule = create(:automation_rule, account: account, actions: [{ action_name: 'send_whatsapp_template',
                                                                  action_params: [template_params.merge('inbox_id' => channel.inbox.id)] }])
    AutomationRules::ActionService.new(rule, account, conversation).perform
    expect(conversation.messages.where(message_type: :outgoing, private: false)).to be_empty
    expect(channel.reload.message_templates.pluck('name')).not_to include(draft.name)
  end

  it 'does not replace the installed campaign content with a local draft of the same identity' do
    installed = channel.message_templates.find { |template| template['name'] == 'test_no_params_template' }
    draft.update!(name: installed.fetch('name'), language: installed.fetch('language'))
    params = { 'name' => installed.fetch('name'), 'language' => installed.fetch('language'), 'processed_params' => {} }
    campaign = create(:campaign, account: account, inbox: channel.inbox, template_params: params)
    contact = create(:contact, account: account, phone_number: '+593991234567')
    recipient = create(:campaign_recipient, campaign: campaign, account: account, contact: contact, inbox: channel.inbox)
    service = Whatsapp::OneoffCampaignService.new(campaign: campaign)
    allow(service).to receive(:channel).and_return(channel)
    allow(channel).to receive(:send_template).and_return('wamid.remote')
    service.send(:send_whatsapp_template_message, recipient: recipient, to: contact.phone_number, template_params: campaign.template_params)
    expect(channel).to have_received(:send_template).with(contact.phone_number, hash_including(name: installed.fetch('name')), anything)
    expect(channel.reload.message_templates.find { |template| template['name'] == draft.name }).to eq(installed)
  end
end
