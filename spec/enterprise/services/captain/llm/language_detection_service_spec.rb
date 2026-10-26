require 'rails_helper'

RSpec.describe Captain::Llm::LanguageDetectionService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, text: 'Bonjour') }

  before do
    stub_const('Schematist', Module.new)
    stub_const('Schematist::Schema', Class.new do
      def self.string(name, **) = (@fields ||= []) << name

      def self.fields = @fields || []
    end)
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
  end

  it 'sends the text to the language detection schema' do
    expect(service).to receive(:make_api_call).with(
      feature: 'language_detection',
      messages: [hash_including(role: 'system'), { role: 'user', content: 'Bonjour' }],
      schema: Captain::Llm::LanguageDetectionSchema
    ).and_return(message: { 'language' => 'fr' })

    expect(service.language).to eq('fr')
    expect(Captain::Llm::LanguageDetectionSchema.fields).to eq([:language])
  end

  it 'returns nil for unknown or missing languages' do
    allow(service).to receive(:perform).and_return(message: { 'language' => 'und' })
    expect(service.language).to be_nil
    allow(service).to receive(:perform).and_return(message: {})
    expect(service.language).to be_nil
  end

  it 'returns nil and logs when detection fails' do
    allow(service).to receive(:perform).and_return(error: 'unavailable')
    expect(Rails.logger).to receive(:warn).with('[AutoTranslate] language detection failed: unavailable')
    expect(service.language).to be_nil
  end
end
