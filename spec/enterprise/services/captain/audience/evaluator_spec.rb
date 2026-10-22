require 'rails_helper'

RSpec.describe Captain::Audience::Evaluator do
  let(:account) { create(:account, settings: { country_code: 'EC' }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+593991234567', email: 'ana@miempresa.com') }
  let(:conversation) { build(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:rules) { {} }
  let(:mode) { 'custom' }
  let!(:connection) do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox, audience_mode: mode, audience_rules: rules)
  end
  let(:evaluation) { described_class.new(assistant, inbox).result(contact, conversation) }
  let(:phone_tree) do
    { 'attribute_key' => 'phone_number', 'filter_operator' => 'contains', 'values' => ['+593'] }
  end

  context 'with allowed phones' do
    let(:rules) { { 'phones' => { 'mode' => 'allow', 'list' => ['+593991234567'] } } }

    it 'accepts a listed phone (matrix 1)' do
      expect(evaluation).to eq(engages: true, reason: nil, condition: nil)
    end

    it 'rejects another phone (matrix 2)' do
      contact.phone_number = '+593980000000'

      expect(evaluation).to include(engages: false, reason: 'audience_not_allowed', condition: { attribute_key: 'phone_number' })
    end

    it 'explains a missing phone including BSUID contacts (matrix 6)' do
      contact.phone_number = nil

      expect(evaluation).to include(engages: false, reason: 'audience_missing_data')
    end

    it 'does not affect another inbox using the same assistant' do
      other_inbox = create(:inbox, account: account)
      other_conversation = build(:conversation, account: account, inbox: other_inbox, contact: contact)
      create(:captain_inbox, captain_assistant: assistant, inbox: other_inbox)
      contact.phone_number = nil

      expect(described_class.new(assistant, other_inbox).result(contact, other_conversation)[:engages]).to be(true)
    end

    it 'rejects all contacts with an empty allowed list' do
      connection.update!(audience_rules: { phones: { mode: 'allow', list: [] } })

      expect(evaluation[:reason]).to eq('audience_not_allowed')
    end
  end

  context 'with a locally written allowed phone' do
    let(:rules) { { 'phones' => { 'mode' => 'allow', 'list' => ['0991 234-567'] } } }

    it 'normalizes both sides (matrix 3)' do
      contact.phone_number = '+593 991-234-567'

      expect(evaluation[:engages]).to be(true)
    end
  end

  context 'with denied phones' do
    let(:rules) do
      { 'phones' => { 'mode' => 'deny', 'list' => ['+593991234567'] },
        'emails' => { 'mode' => 'allow', 'list' => ['ana@miempresa.com'] } }
    end

    it 'denies even when another allowed list matches (matrix 4 and representable part of 5)' do
      expect(evaluation).to include(engages: false, reason: 'audience_denied')
    end

    it 'checks denied lists before a missing allowed value' do
      contact.email = nil

      expect(evaluation[:reason]).to eq('audience_denied')
    end

    it 'accepts an empty denied list' do
      connection.update!(audience_rules: { phones: { mode: 'deny', list: [] } })

      expect(evaluation[:engages]).to be(true)
    end
  end

  context 'with Instagram contacts without a phone' do
    let(:inbox) { create(:channel_instagram, account: account).inbox }

    before { contact.phone_number = nil }

    it 'rejects an allowed phone list' do
      connection.update!(audience_rules: { phones: { mode: 'allow', list: ['+593991234567'] } })

      expect(evaluation[:reason]).to eq('audience_missing_data')
    end

    it 'accepts a denied phone list' do
      connection.update!(audience_rules: { phones: { mode: 'deny', list: ['+593991234567'] } })

      expect(evaluation[:engages]).to be(true)
    end
  end

  context 'with channel IDs' do
    let(:rules) { { 'channel_ids' => { 'mode' => 'allow', 'list' => ['usuarioA'] } } }

    it 'accepts an Instagram username (matrix 8)' do
      contact.additional_attributes['social_instagram_user_name'] = 'usuarioA'

      expect(evaluation[:engages]).to be(true)
    end

    it 'also reads the stored social profile username' do
      contact.additional_attributes['social_profiles'] = { 'instagram' => 'usuarioA' }

      expect(evaluation[:engages]).to be(true)
    end

    it 'accepts the conversation source ID' do
      conversation.contact_inbox.source_id = 'usuarioA'

      expect(evaluation[:engages]).to be(true)
    end

    it 'rejects another user (matrix 9)' do
      conversation.contact_inbox.source_id = 'usuarioB'

      expect(evaluation[:reason]).to eq('audience_not_allowed')
    end

    it 'explains missing IDs' do
      conversation.contact_inbox = nil

      expect(evaluation).to include(reason: 'audience_missing_data', condition: { attribute_key: 'channel_ids' })
    end
  end

  context 'with allowed email domains' do
    let(:rules) { { 'emails' => { 'mode' => 'allow', 'list' => ['@MIEMPRESA.COM'] } } }

    it 'rejects anonymous visitors (matrix 10)' do
      contact.email = nil

      expect(evaluation[:reason]).to eq('audience_missing_data')
    end

    it 'matches exact domains without case sensitivity (matrix 12)' do
      expect(evaluation[:engages]).to be(true)
    end

    it 'does not match subdomains or suffix lookalikes' do
      contact.email = 'ana@otra.miempresa.com'

      expect(evaluation[:reason]).to eq('audience_not_allowed')
    end
  end

  context 'with denied email addresses' do
    let(:rules) { { 'emails' => { 'mode' => 'deny', 'list' => ['ANA@MIEMPRESA.COM'] } } }

    it 'compares exact email addresses without case sensitivity' do
      expect(evaluation[:reason]).to eq('audience_denied')
    end

    it 'lets a contact without an email through' do
      contact.email = nil

      expect(evaluation[:engages]).to be(true)
    end
  end

  context 'with condition trees' do
    it 'uses HMAC verification (matrix 11)' do
      connection.update!(audience_rules: { tree: { attribute_key: 'hmac_verified', filter_operator: 'equal_to', values: ['true'] } })
      conversation.contact_inbox.hmac_verified = true

      expect(evaluation[:engages]).to be(true)
    end

    it 'accepts contact labels (matrix 14)' do
      contact.label_list.add('VIP')
      connection.update!(audience_rules: { tree: { attribute_key: 'labels', filter_operator: 'equal_to', values: ['VIP'] } })

      expect(evaluation[:engages]).to be(true)
    end

    it 'returns the failing tree condition after lists pass' do
      contact.phone_number = nil
      connection.update!(audience_rules: { tree: phone_tree })

      expect(evaluation).to eq(engages: false, reason: 'audience_missing_data', condition: phone_tree)
    end
  end

  context 'with inherited rules' do
    let(:mode) { 'inherit' }
    let(:rules) { { 'emails' => { 'mode' => 'deny', 'list' => ['ana@miempresa.com'] } } }

    it 'keeps the base matcher behavior with a missing phone (matrix 7)' do
      assistant.config['audience'] = phone_tree
      contact.phone_number = nil

      expect(evaluation).to eq(engages: false, reason: 'audience_missing_data', condition: phone_tree)
    end

    it 'ignores stored custom rules and accepts an empty base (matrix 17)' do
      expect(evaluation[:engages]).to be(true)
    end

    it 'preserves an ordinary base rejection' do
      assistant.config['audience'] = phone_tree
      contact.phone_number = '+14155552671'

      expect(evaluation[:reason]).to eq('audience_no_match')
    end
  end

  context 'with everyone mode' do
    let(:mode) { 'everyone' }
    let(:rules) { { 'phones' => { 'mode' => 'deny', 'list' => ['+593991234567'] }, 'contact_scope' => 'returning' } }

    it 'skips the base and all custom restrictions' do
      assistant.config['audience'] = phone_tree
      contact.phone_number = nil

      expect(evaluation[:engages]).to be(true)
    end

    it 'still applies the schedule' do
      allow(assistant).to receive(:available_now?).with(conversation).and_return(false)

      expect(evaluation).to eq(engages: false, reason: 'out_of_hours', condition: nil)
    end
  end

  it 'replaces the base with custom rules and preserves the boolean contract' do
    assistant.config['audience'] = phone_tree
    contact.phone_number = nil

    expect(assistant.engagement_result(contact, conversation)[:engages]).to be(true)
    expect(assistant.engages?(contact, conversation)).to be(true)
  end

  it 'applies the schedule last (matrix 16)' do
    assistant.config['response_window'] = 'outside_business_hours'
    allow(inbox).to receive_messages(working_hours_enabled?: true, out_of_office?: false)

    expect(evaluation[:reason]).to eq('out_of_hours')
  end

  context 'with contact scope' do
    let(:rules) { { 'contact_scope' => 'new' } }

    it 'accepts a contact without previous conversations' do
      expect(evaluation[:engages]).to be(true)
    end

    it 'counts previous conversations in other inboxes of the account (matrix 13)' do
      create(:conversation, account: account, contact: contact)

      expect(evaluation).to eq(engages: false, reason: 'audience_scope', condition: { contact_scope: 'new' })
    end

    it 'does not count conversations in another account' do
      other_account = create(:account)
      create(:conversation, account: other_account, contact: contact)

      expect(evaluation[:engages]).to be(true)
    end

    it 'excludes the current conversation when persisted' do
      conversation.save!

      expect(evaluation[:engages]).to be(true)
    end

    it 'does not reclassify an earlier conversation because of a later opening' do
      conversation.save!
      create(:conversation, account: account, contact: contact, created_at: conversation.created_at + 1.minute)

      expect(evaluation[:engages]).to be(true)
    end

    it 'rejects a new customer when only returning customers are allowed' do
      connection.update!(audience_rules: { contact_scope: 'returning' })

      expect(evaluation).to include(reason: 'audience_scope', condition: { contact_scope: 'returning' })
    end

    it 'accepts a returning customer' do
      create(:conversation, account: account, contact: contact)
      connection.update!(audience_rules: { contact_scope: 'returning' })

      expect(evaluation[:engages]).to be(true)
    end
  end
end
