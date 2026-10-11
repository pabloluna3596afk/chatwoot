require 'rails_helper'

RSpec.describe Captain::Conversation::MessageBuilder do
  let(:account) { create(:account, locale: 'es') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:flow) { create(:whatsapp_flow, account: account, name: 'Datos de reserva') }
  let(:messaging) do
    { 'inboxes' => [{ 'inbox_id' => inbox.id, 'enabled' => true, 'flows' => [{ 'flow_id' => flow.id, 'purpose' => 'Pedir datos' }],
                      'templates' => [] }] }
  end
  let(:assistant) { create(:captain_assistant, account: account, config: { 'messaging' => messaging }) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:request) { Captain::Messaging::Request.new(kind: 'flow', resource: flow.id, responding_to_message_id: 41) }
  let(:host_class) do
    Class.new do
      include Captain::Conversation::MessageBuilder

      attr_reader :account, :inbox

      def initialize(conversation, assistant, responding_to_message_id)
        @conversation = conversation
        @assistant = assistant
        @account = conversation.account
        @inbox = conversation.inbox
        @responding_to_message_id = responding_to_message_id
        @response = { 'response' => 'Te envío el formulario.' }
      end

      def captain_v2_enabled? = true

      def build = create_messages
    end
  end
  let(:builder) { host_class.new(conversation, assistant, 41) }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    WhatsappFlowPublication.create!(whatsapp_flow: flow, account: account, waba_id: channel.provider_config['business_account_id'],
                                    status: 'published', meta_flow_id: '1234567', published_at: Time.current)
    allow_any_instance_of(Conversation).to receive(:can_reply?).and_return(true) # rubocop:disable RSpec/AnyInstance
  end

  after { Redis::Alfred.delete(format(Redis::RedisKeys::CAPTAIN_MESSAGING_INTENT, conversation_id: conversation.id)) }

  it 'sends the prepared Flow instead of the text of the model' do
    Captain::Messaging::Intent.stash(conversation, request)

    message = builder.build

    expect(message.additional_attributes).to include('whatsapp_flow' => hash_including('id' => flow.id))
    expect(message.sender).to eq(assistant)
    expect(conversation.messages.where(private: false, message_type: :outgoing).pluck(:content)).not_to include('Te envío el formulario.')
    expect(conversation.messages.where(private: true).last.content).to eq('Captain envió el Flow Datos de reserva')
  end

  it 'posts the reply of the model, with a private note, when the prepared Flow can no longer be sent' do
    Captain::Messaging::Intent.stash(conversation, request)
    flow.whatsapp_flow_publications.destroy_all

    message = builder.build

    expect(message.content).to eq('Te envío el formulario.')
    expect(conversation.messages.where(private: true).last.content).to start_with('Captain no pudo enviar el Flow o la plantilla que preparó')
  end

  it 'posts the reply of the model as usual when no tool prepared anything' do
    expect(builder.build.content).to eq('Te envío el formulario.')
    expect(conversation.messages.where(private: true)).to be_empty
  end
end
