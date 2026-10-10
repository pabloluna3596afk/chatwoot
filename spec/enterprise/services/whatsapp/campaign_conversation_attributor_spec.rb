require 'rails_helper'

RSpec.describe Whatsapp::CampaignConversationAttributor do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+16503071063') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '16503071063') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:template_params) do
    {
      'name' => 'ticket_status_updated',
      'namespace' => '23423423_2342423_324234234_2343224',
      'category' => 'UTILITY',
      'language' => 'en',
      'processed_params' => { 'name' => 'John', 'ticket_id' => '2332' }
    }
  end
  let(:campaign) do
    create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, template_params: template_params)
  end
  let(:context_id) { 'wamid.ORIGINAL_MESSAGE_ID' }
  let(:message_payload) do
    {
      context: { from: '16503071063', id: context_id },
      from: '16503071063',
      id: 'wamid.REPLY_MESSAGE_ID',
      text: { body: 'Yes' },
      type: 'text'
    }.with_indifferent_access
  end
  let(:sent_at) { 2.hours.ago.change(usec: 0) }

  before { account.enable_features!(:whatsapp_campaign) }

  def create_recipient(for_campaign: campaign, for_inbox: inbox)
    CampaignRecipient.create!(
      account: account,
      campaign: for_campaign,
      contact: contact,
      inbox: for_inbox,
      status: :sent,
      source_id: context_id,
      sent_at: sent_at
    )
  end

  def perform_attribution(payload = message_payload)
    described_class.new(
      conversation: conversation,
      inbox: inbox,
      message_payload: payload,
      outgoing_echo: false
    ).perform
  end

  it 'sets campaign_id when context.id matches a campaign recipient' do
    create_recipient

    perform_attribution

    expect(conversation.reload.campaign_id).to eq(campaign.id)
  end

  it 'does not change campaign_id when context is missing' do
    create_recipient

    perform_attribution(message_payload.except(:context))

    expect(conversation.reload.campaign_id).to be_nil
    expect(conversation.messages.count).to eq(0)
  end

  it 'does not overwrite an existing campaign_id' do
    other_campaign = create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, title: 'Other')
    conversation.update!(campaign_id: other_campaign.id)
    create_recipient

    perform_attribution

    expect(conversation.reload.campaign_id).to eq(other_campaign.id)
    expect(conversation.messages.count).to eq(0)
  end

  it 'does not attribute from a recipient in another inbox' do
    other_channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                                              sync_templates: false, validate_provider_config: false)
    other_campaign = create(:campaign, account: account, inbox: other_channel.inbox, campaign_type: :one_off,
                                       template_params: template_params)
    create_recipient(for_campaign: other_campaign, for_inbox: other_channel.inbox)

    perform_attribution

    expect(conversation.reload.campaign_id).to be_nil
  end

  describe 'the campaign message shown in the chat' do
    let!(:reply) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                       source_id: 'wamid.REPLY_MESSAGE_ID', content: 'Yes',
                       content_attributes: { 'in_reply_to_external_id' => context_id })
    end

    before { create_recipient }

    it 'adds what the campaign sent, dated when it was sent and carrying the campaign' do
      perform_attribution

      message = conversation.messages.find_by(source_id: context_id)
      expect(message).to be_outgoing
      expect(message.additional_attributes['campaign_id']).to eq(campaign.id)
      expect(message.additional_attributes['template_params']['name']).to eq('ticket_status_updated')
      expect(message.created_at).to eq(sent_at)
    end

    it 'points the reply at the campaign message' do
      perform_attribution

      message = conversation.messages.find_by(source_id: context_id)
      expect(reply.reload.content_attributes['in_reply_to']).to eq(message.id)
    end

    it 'keeps the conversation as recent as the reply' do
      activity = conversation.reload.last_activity_at

      perform_attribution

      expect(conversation.reload.last_activity_at).to eq(activity)
    end

    it 'does not add the message twice' do
      perform_attribution
      conversation.update!(campaign_id: nil)

      expect { perform_attribution }.not_to(change { conversation.messages.count })
    end

    it 'adds nothing when the campaign has no template' do
      campaign.update_columns(template_params: nil) # rubocop:disable Rails/SkipsModelValidations

      perform_attribution

      expect(conversation.reload.campaign_id).to eq(campaign.id)
      expect(conversation.messages.where(source_id: context_id)).to be_empty
    end
  end
end
