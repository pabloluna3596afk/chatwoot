require 'rails_helper'

RSpec.describe Captain::Messaging::Intent do
  let(:conversation) { create(:conversation) }
  let(:flow_request) { Captain::Messaging::Request.new(kind: 'flow', resource: 7, responding_to_message_id: 41, intro_text: 'Hola') }
  let(:template_request) do
    Captain::Messaging::Request.new(kind: 'template', resource: { name: 'cita', language: 'es' }, responding_to_message_id: 41)
  end

  after { Redis::Alfred.delete(format(Redis::RedisKeys::CAPTAIN_MESSAGING_INTENT, conversation_id: conversation.id)) }

  it 'gives back the request for the same customer message, once' do
    expect(described_class.stash(conversation, flow_request)).to be(true)

    taken = described_class.take(conversation, responding_to: 41)

    expect(taken).to have_attributes(kind: 'flow', resource: 7, intro_text: 'Hola', responding_to_message_id: 41)
    expect(described_class.take(conversation, responding_to: 41)).to be_nil
  end

  it 'keeps the name and language of a template' do
    described_class.stash(conversation, template_request)

    expect(described_class.take(conversation, responding_to: 41).resource).to eq(name: 'cita', language: 'es')
  end

  it 'accepts one request per customer message' do
    described_class.stash(conversation, flow_request)

    expect(described_class.stash(conversation, template_request)).to be(false)
    expect(described_class.take(conversation, responding_to: 41).kind).to eq('flow')
  end

  it 'drops a request stashed for another customer message' do
    described_class.stash(conversation, flow_request)

    expect(described_class.take(conversation, responding_to: 42)).to be_nil
    expect(described_class.take(conversation, responding_to: 41)).to be_nil
  end
end
