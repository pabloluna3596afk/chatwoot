require 'rails_helper'

RSpec.describe Captain::Conversation::MessageBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:items) do
    [{ 'title' => 'Sí, reservar', 'value' => 'yes_book:2030-01-15T10:00:00-05:00' }, { 'title' => 'Otra hora', 'value' => 'other_time' }]
  end
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
        @response = { 'response' => '¿Te reservo el martes 15 a las 10:00?' }
      end

      def captain_v2_enabled? = true

      def build = create_messages
    end
  end
  let(:builder) { host_class.new(conversation, assistant, 41) }

  after { Redis::Alfred.delete(format(Redis::RedisKeys::CAPTAIN_QUICK_REPLIES, conversation_id: conversation.id)) }

  it 'sends the reply as an input_select message carrying the buttons a tool stashed' do
    Captain::QuickReplies.stash(conversation, items, responding_to: 41)

    message = builder.build

    expect(message).to have_attributes(
      content: '¿Te reservo el martes 15 a las 10:00?', content_type: 'input_select', message_type: 'outgoing', sender: assistant
    )
    expect(message.content_attributes['items']).to eq(items)
  end

  it 'uses the buttons only once' do
    Captain::QuickReplies.stash(conversation, items, responding_to: 41)

    builder.build
    second = builder.build

    expect(second.content_type).to eq('text')
    expect(second.content_attributes['items']).to be_blank
  end

  it 'sends a plain text reply when no tool asked for buttons' do
    message = builder.build

    expect(message).to have_attributes(content: '¿Te reservo el martes 15 a las 10:00?', content_type: 'text')
  end

  it 'does not attach buttons stashed for another customer message' do
    Captain::QuickReplies.stash(conversation, items, responding_to: 40)

    expect(builder.build.content_type).to eq('text')
  end

  it 'builds the WhatsApp reply buttons from the stashed items (3 or fewer)' do
    Captain::QuickReplies.stash(conversation, items, responding_to: 41)
    message = builder.build

    payload = Whatsapp::Providers::WhatsappCloudService.allocate.send(:create_payload_based_on_items, message)

    expect(payload[:type]).to eq('button')
    expect(payload[:body][:text]).to eq('¿Te reservo el martes 15 a las 10:00?')
    expect(payload[:action]['buttons'].map { |button| button['reply'] }).to eq(
      [{ 'id' => 'yes_book:2030-01-15T10:00:00-05:00', 'title' => 'Sí, reservar' }, { 'id' => 'other_time', 'title' => 'Otra hora' }]
    )
  end

  it 'builds a WhatsApp list when there are more than three options' do
    many = Array.new(6) { |index| { 'title' => "mar 15 · 0#{index}:00", 'value' => "2030-01-15T0#{index}:00:00-05:00" } }
    Captain::QuickReplies.stash(conversation, many, responding_to: 41)
    message = builder.build

    payload = Whatsapp::Providers::WhatsappCloudService.allocate.send(:create_payload_based_on_items, message)

    expect(payload[:type]).to eq('list')
    expect(payload[:action]['sections'].first['rows'].size).to eq(6)
    expect(payload[:action]['sections'].first['rows'].first).to eq('id' => '2030-01-15T00:00:00-05:00', 'title' => 'mar 15 · 00:00')
  end
end
