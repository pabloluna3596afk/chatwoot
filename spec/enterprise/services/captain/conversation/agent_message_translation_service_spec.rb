require 'rails_helper'

RSpec.describe Captain::Conversation::AgentMessageTranslationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, additional_attributes: { 'conversation_language' => 'fr' })
  end
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     sender: user, content: 'Hello', content_attributes: { 'translation_pending' => true })
  end
  let(:translator) do
    instance_double(Captain::Conversation::TranslatorService, provider: 'captain', language: 'en', translate: 'Bonjour')
  end

  before do
    allow(Captain::Conversation::TranslatorService).to receive(:new).and_return(translator)
  end

  it 'translates a public agent reply and retains the original with provider metadata' do
    user.update!(ui_settings: { locale: 'en' })

    described_class.new(message: message).perform

    expect(message.reload.content).to eq('Bonjour')
    expect(message.translations).to eq('en' => 'Hello')
    expect(message.source_language).to eq('fr')
    expect(message.translation_provider).to eq('captain')
    expect(message.content_attributes).not_to have_key('translation_pending')
  end

  it 'leaves a private note unchanged' do
    private_note = create(:message, account: account, inbox: inbox, conversation: conversation,
                                    message_type: :outgoing, sender: user, private: true, content: 'Internal note')

    described_class.new(message: private_note).perform

    expect(translator).not_to have_received(:translate)
    expect(private_note.reload.content).to eq('Internal note')
  end
end
