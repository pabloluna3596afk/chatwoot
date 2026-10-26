require 'rails_helper'

RSpec.describe Captain::Conversation::MessageLanguageService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, message_type: :incoming, content: 'Bonjour') }
  let(:translator) { instance_double(Captain::Conversation::TranslatorService, language: 'fr') }

  it 'detects, saves and applies the language from the latest incoming public text message' do
    allow(Captain::Conversation::TranslatorService).to receive(:new).with(account: account).and_return(translator)

    expect(described_class.new(conversation: conversation, message: message).perform).to eq('fr')
    expect(message.reload.source_language).to eq('fr')
    expect(conversation.reload.additional_attributes['conversation_language']).to eq('fr')
  end

  it 'reuses an existing source language' do
    message.update!(source_language: 'es')
    expect(Captain::Conversation::TranslatorService).not_to receive(:new)
    expect(described_class.new(conversation: conversation, message: message).perform).to eq('es')
  end

  it 'does not persist an undetected language' do
    allow(translator).to receive(:language).and_return(nil)
    allow(Captain::Conversation::TranslatorService).to receive(:new).with(account: account).and_return(translator)
    expect(described_class.new(conversation: conversation, message: message).perform).to be_nil
    expect(message.reload.source_language).to be_nil
  end
end
