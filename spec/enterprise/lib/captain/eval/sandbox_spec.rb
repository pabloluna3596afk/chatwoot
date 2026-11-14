require 'rails_helper'

RSpec.describe Captain::Eval::Sandbox do
  subject(:sandbox) { described_class.new.prepare(pilot: false) }

  let(:embedding) { [1.0] + Array.new(1535, 0.0) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService, get_embedding: embedding) }

  before { allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service) }

  it 'creates an API inbox, a planless account and explicitly disables pilot' do
    expect(sandbox.inbox.channel).to be_a(Channel::Api)
    expect(sandbox.inbox.channel.webhook_url).to be_nil
    expect(sandbox.account.plan).to be_nil
    expect(sandbox.account.feature_enabled?('captain_integration_v2')).to be true
    expect(Captain::Pilot.enabled?(sandbox.account)).to be false
  end

  it 'reuses the account, removes previous conversations and switches pilot on' do
    previous = sandbox.conversation_for('citas-01')
    other_conversation = create(:conversation)
    next_sandbox = described_class.new.prepare(pilot: true)
    expect(next_sandbox.account.id).to eq(sandbox.account.id)
    expect(Conversation.exists?(previous.id)).to be false
    expect(Conversation.exists?(other_conversation.id)).to be true
    expect(Captain::Pilot.enabled?(next_sandbox.account)).to be true
  end

  it 'creates approved knowledge with inline embeddings and no embedding job' do
    vertical = Captain::Eval::Suite.new(names: 'citas').verticals.sole
    expect(Captain::Llm::UpdateEmbeddingJob).not_to receive(:perform_later)
    assistant = sandbox.assistant_for(vertical)
    expect(assistant.responses.approved.count).to eq(8)
    expect(assistant.responses.first.embedding).to eq(embedding)
    expect(assistant.response_guidelines).to eq(vertical['assistant']['guidelines'])
    sandbox.assistant_for(vertical)
    expect(assistant.responses.count).to eq(8)
  end

  it 'persists history without delivery jobs or automatic Captain responses' do
    conversation = sandbox.conversation_for('citas-01')
    expect(SendReplyJob).not_to receive(:perform_later)
    expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)
    sandbox.add_message(conversation, content: 'hola', sender: conversation.contact, message_type: :incoming)
    expect(Captain::Conversation::MessageHistoryBuilderService.new(conversation: conversation).perform).to include(hash_including(role: 'user'))
  end
end
