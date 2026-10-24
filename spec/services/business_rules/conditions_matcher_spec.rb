require 'rails_helper'

RSpec.describe BusinessRules::ConditionsMatcher do
  describe '.match?' do
    it 'preserves campaign conditions normalized by embedded business rules' do
      account = create(:account)
      campaign = create(:campaign, account: account)
      conversation = create(:conversation, account: account, campaign: campaign)
      conditions = [{ 'attribute_key' => 'campaign_id', 'filter_operator' => 'equal_to',
                      'values' => [{ 'id' => campaign.id.to_s, 'name' => campaign.title }] }]

      expect(described_class.match?(account: account, conversation: conversation, conditions: conditions)).to be(true)

      conversation.update!(campaign_id: nil)

      expect(described_class.match?(account: account, conversation: conversation, conditions: conditions)).to be(false)
    end
  end
end
