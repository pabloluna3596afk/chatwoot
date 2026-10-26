require 'rails_helper'

RSpec.describe Captain::Conversation::ContactMessageTranslationService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Bonjour')
  end
  let(:translator) { instance_double(Captain::Conversation::TranslatorService, provider: 'captain', translate: 'Hello') }

  before do
    allow(Captain::Conversation::MessageLanguageService).to receive(:new)
      .and_return(instance_double(Captain::Conversation::MessageLanguageService, perform: 'fr'))
    allow(Captain::Conversation::TranslatorService).to receive(:new).and_return(translator)
  end

  it 'stores a public contact message translation for the requested language' do
    described_class.new(message: message, target_language: 'en').perform

    expect(message.reload.translations).to eq('en' => 'Hello')
    expect(message.translation_provider).to eq('captain')
    expect(message.content_attributes['translation_status']).to eq('completed')
  end

  it 'marks a translation as failed when the provider returns no text' do
    allow(translator).to receive(:translate).and_return(nil)

    described_class.new(message: message, target_language: 'en').perform

    expect(message.reload.translation_failed).to be true
    expect(message.content_attributes['translation_status']).to eq('failed')
  end

  it 'does not translate a private note' do
    private_message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                       message_type: :incoming, private: true, content: 'Bonjour')

    described_class.new(message: private_message, target_language: 'en').perform

    expect(translator).not_to have_received(:translate)
    expect(private_message.reload.translations).to be_nil
  end
end
