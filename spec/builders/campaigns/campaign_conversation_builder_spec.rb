require 'rails_helper'

describe Campaigns::CampaignConversationBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, identifier: '123') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:campaign) { create(:campaign, inbox: inbox, account: account, trigger_rules: { url: 'https://test.com' }) }

  describe '#perform' do
    it 'creates a conversation with campaign id and message with campaign message' do
      campaign_conversation = described_class.new(
        contact_inbox_id: contact_inbox.id,
        campaign_display_id: campaign.display_id
      ).perform

      expect(campaign_conversation.campaign_id).to eq(campaign.id)
      expect(campaign_conversation.messages.first.content).to eq(campaign.message)
      expect(campaign_conversation.messages.first.additional_attributes['campaign_id']).to eq(campaign.id)
    end

    it 'will not create a conversation with campaign id if another conversation exists' do
      create(:conversation, contact_inbox_id: contact_inbox.id, inbox: inbox, account: account)
      campaign_conversation = described_class.new(
        contact_inbox_id: contact_inbox.id,
        campaign_display_id: campaign.display_id
      ).perform

      expect(campaign_conversation).to be_nil
    end
  end

  it 'resolves contact data only when the visitor creates the conversation' do
    contact.update!(name: 'ANA maria')
    campaign.update!(message: 'Hola {{ contact.name }}')
    conversation = described_class.new(contact_inbox_id: contact_inbox.id, campaign_display_id: campaign.display_id).perform
    expect(conversation.messages.sole.content).to eq('Hola Ana Maria')
  end

  it 'rolls back conversation creation when required contact data is missing' do
    contact.update!(email: nil)
    campaign.update!(message: 'Correo: {{ contact.email }}')
    expect do
      expect(described_class.new(contact_inbox_id: contact_inbox.id, campaign_display_id: campaign.display_id).perform).to be_nil
    end.not_to change(Conversation, :count)
  end
end
