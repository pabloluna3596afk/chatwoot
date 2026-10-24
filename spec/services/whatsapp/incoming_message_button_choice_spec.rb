require 'rails_helper'

RSpec.shared_examples 'WhatsApp button choice changes' do |provider|
  let(:channel) do
    create(:channel_whatsapp, provider: provider, sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: channel.account, phone_number: '+593991234567') }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '593991234567') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let!(:outgoing) do
    create(:message, conversation: conversation, account: channel.account, message_type: :outgoing, source_id: 'wamid.menu')
  end
  let(:context) { { id: outgoing.source_id } }
  let(:reply_type) { 'button' }
  let(:reply) do
    if reply_type == 'button'
      { type: 'button', button: { text: 'Sales', payload: 'sales' } }
    else
      { type: 'interactive', interactive: { :type => reply_type, reply_type => { id: 'sales', title: 'Sales' } } }
    end
  end
  let(:value) do
    { contacts: [{ profile: { name: 'Customer' }, wa_id: '593991234567' }],
      messages: [{ from: '593991234567', id: 'wamid.choice', timestamp: Time.current.to_i.to_s, context: context }.merge(reply)] }
  end
  let(:params) do
    payload = provider == 'whatsapp_cloud' ? { entry: [{ changes: [{ value: value }] }] } : value
    payload.with_indifferent_access
  end
  let(:previous) do
    create(:message, conversation: conversation, account: channel.account, content: 'Support',
                     content_attributes: { in_reply_to: outgoing.id })
  end
  let(:incoming) { conversation.messages.incoming.reorder(:id).last }

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
  end

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  it 'marks a repeated choice too, without discarding the new message' do
    previous.update!(content: 'Sales')

    expect { described_class.new(inbox: channel.inbox, params: params).perform }
      .to change { conversation.messages.incoming.count }.by(1)

    expect(incoming.content_attributes).to include('button_choice_changed' => true, 'previous_button_choice' => 'Sales')
  end

  it 'does not count an outgoing reply as a previous customer choice' do
    create(:message, conversation: conversation, account: channel.account, message_type: :outgoing,
                     content_attributes: { in_reply_to: outgoing.id })

    described_class.new(inbox: channel.inbox, params: params).perform

    expect(incoming.content_attributes).not_to have_key('button_choice_changed')
  end

  %w[button button_reply list_reply].each do |type|
    context "with #{type}" do
      let(:reply_type) { type }

      it 'leaves the first choice unmarked' do
        described_class.new(inbox: channel.inbox, params: params).perform

        expect(incoming.content_attributes).to include('in_reply_to' => outgoing.id)
        expect(incoming.content_attributes).not_to have_key('button_choice_changed')
        expect(incoming.content_attributes).not_to have_key('previous_button_choice')
      end

      it 'saves the second choice normally with the previous choice' do
        previous

        expect { described_class.new(inbox: channel.inbox, params: params).perform }
          .to change { conversation.messages.incoming.count }.by(1)

        expect(incoming.content).to eq(type == 'button' ? 'Sales' : 'sales')
        expect(incoming.content_attributes).to include('button_choice_changed' => true, 'previous_button_choice' => 'Support')
      end

      it 'uses the most recent previous choice on the third tap, with id breaking timestamp ties' do
        previous
        create(:message, conversation: conversation, account: channel.account, content: 'Billing', created_at: previous.created_at,
                         content_attributes: { in_reply_to: outgoing.id })

        described_class.new(inbox: channel.inbox, params: params).perform

        expect(incoming.content_attributes).to include('button_choice_changed' => true, 'previous_button_choice' => 'Billing')
      end

      it 'does not mix choices from distinct outgoing messages' do
        previous
        other = create(:message, conversation: conversation, account: channel.account, message_type: :outgoing, source_id: 'wamid.other')
        params_value = provider == 'whatsapp_cloud' ? params[:entry][0][:changes][0][:value] : params
        params_value[:messages][0][:context][:id] = other.source_id

        described_class.new(inbox: channel.inbox, params: params).perform

        expect(incoming.content_attributes).to include('in_reply_to' => other.id)
        expect(incoming.content_attributes).not_to have_key('button_choice_changed')
      end
    end
  end

  context 'without context' do
    let(:context) { nil }

    it 'does not guess the outgoing message' do
      previous
      described_class.new(inbox: channel.inbox, params: params).perform

      expect(incoming.content_attributes).not_to have_key('in_reply_to')
      expect(incoming.content_attributes).not_to have_key('button_choice_changed')
    end
  end

  context 'with an unknown context' do
    let(:context) { { id: 'wamid.unknown' } }

    it 'does not guess the outgoing message' do
      previous
      described_class.new(inbox: channel.inbox, params: params).perform

      expect(incoming.content_attributes).not_to have_key('in_reply_to')
      expect(incoming.content_attributes).not_to have_key('button_choice_changed')
    end
  end

  context 'with a text reply' do
    let(:reply) { { type: 'text', text: { body: 'Sales' } } }

    it 'keeps ordinary replies unchanged' do
      previous
      described_class.new(inbox: channel.inbox, params: params).perform

      expect(incoming.content).to eq('Sales')
      expect(incoming.content_attributes).not_to have_key('button_choice_changed')
    end
  end

  context 'with another interactive type' do
    let(:reply) { { type: 'interactive', interactive: { type: 'nfm_reply', nfm_reply: { response_json: '{"name":"Ana"}' } } } }

    it 'keeps Flow replies outside button choice detection' do
      previous
      described_class.new(inbox: channel.inbox, params: params).perform

      expect(incoming.content_attributes).not_to have_key('button_choice_changed')
    end
  end
end

RSpec.describe Whatsapp::IncomingMessageWhatsappCloudService do
  it_behaves_like 'WhatsApp button choice changes', 'whatsapp_cloud'
end

RSpec.describe Whatsapp::IncomingMessageService do
  it_behaves_like 'WhatsApp button choice changes', 'default'
end
