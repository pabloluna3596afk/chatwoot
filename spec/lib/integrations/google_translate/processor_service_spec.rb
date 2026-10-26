require 'rails_helper'
require 'google/cloud/translate/v3'

RSpec.describe Integrations::GoogleTranslate::ProcessorService do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :google_translate, account: account) }
  let(:client) { instance_double(Google::Cloud::Translate::V3::TranslationService::Client) }

  before do
    allow(Google::Cloud::Translate::V3::TranslationService::Client).to receive(:new).and_return(client)
  end

  it 'translates text and normalizes the target language tag' do
    response = Google::Cloud::Translate::V3::TranslateTextResponse.new(translations: [{ translated_text: 'Hola' }])
    expect(client).to receive(:translate_text).with(
      contents: ['Hello'], target_language_code: 'es-MX', parent: "projects/#{hook.settings['project_id']}",
      mime_type: 'text/plain'
    ).and_return(response)

    expect(described_class.new(hook: hook).translate('Hello', 'es_MX')).to eq('Hola')
  end

  it 'detects language using the first 1500 characters' do
    response = Google::Cloud::Translate::V3::DetectLanguageResponse.new(languages: [{ language_code: 'fr', confidence: 0.9 }])
    request = { content: 'a' * 1500, parent: "projects/#{hook.settings['project_id']}" }
    expect(client).to receive(:detect_language).with(request).and_return(response)

    expect(described_class.new(hook: hook).detect('a' * 1600)).to eq('fr')
  end

  it 'returns nil when there is no configured integration' do
    expect(Google::Cloud::Translate::V3::TranslationService::Client).not_to receive(:new)
    expect(described_class.new.translate('Hello', 'es')).to be_nil
  end
end
