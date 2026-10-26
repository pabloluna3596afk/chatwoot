require 'rails_helper'

RSpec.describe Captain::Conversation::TranslatorService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, conversation_display_id: 17) }

  it 'uses Captain to translate and detect language' do
    translation = instance_double(Captain::Llm::MessageTranslationService, perform: { message: 'Hola' })
    detection = instance_double(Captain::Llm::LanguageDetectionService, language: 'es')
    expect(Captain::Llm::MessageTranslationService).to receive(:new).with(
      account: account, text: 'Hello', target_language: 'es', conversation_display_id: 17
    ).and_return(translation)
    expect(Captain::Llm::LanguageDetectionService).to receive(:new).with(account: account, text: 'Hola').and_return(detection)

    expect(service.translate('Hello', 'es')).to eq('Hola')
    expect(service.language('Hola')).to eq('es')
  end

  it 'uses Google Translate when configured' do
    allow(account).to receive(:translation_service).and_return('google_translate')
    google = instance_double(Integrations::GoogleTranslate::ProcessorService, translate: 'Hola', detect: 'es')
    expect(Integrations::GoogleTranslate::ProcessorService).to receive(:new).with(hook: account.google_translate_hook).and_return(google)

    expect(service.translate('Hello', 'es')).to eq('Hola')
    expect(service.language('Hola')).to eq('es')
  end

  it 'returns nil and logs Google API errors' do
    allow(account).to receive(:translation_service).and_return('google_translate')
    google = instance_double(Integrations::GoogleTranslate::ProcessorService)
    allow(Integrations::GoogleTranslate::ProcessorService).to receive(:new).and_return(google)
    allow(google).to receive(:translate).and_raise(Google::Cloud::Error, 'offline')
    allow(google).to receive(:detect).and_raise(Google::Cloud::Error, 'offline')
    expect(Rails.logger).to receive(:warn).with('[AutoTranslate] Google translation failed: offline')
    expect(Rails.logger).to receive(:warn).with('[AutoTranslate] Google language detection failed: offline')

    expect(service.translate('Hello', 'es')).to be_nil
    expect(service.language('Hello')).to be_nil
  end
end
