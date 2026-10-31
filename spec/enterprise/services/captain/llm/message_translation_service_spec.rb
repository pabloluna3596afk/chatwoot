require 'rails_helper'

RSpec.describe Captain::Llm::MessageTranslationService do
  let(:account) { create(:account) }
  let(:service) do
    described_class.new(account: account, text: "Hello\u0001 world", target_language: 'es-MX', conversation_display_id: 42)
  end

  before do
    stub_const('Schematist', Module.new)
    stub_const('Schematist::Schema', Class.new do
      def self.string(name, **) = (@fields ||= []) << name

      def self.fields = @fields || []
    end)
    stub_const('Captain::Llm::MessageTranslationSchema', Class.new(Schematist::Schema) { string :translation })
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
  end

  it 'translates using the schema and cleans control characters' do
    expect(service).to receive(:make_api_call).with(
      feature: 'message_translation', schema: Captain::Llm::MessageTranslationSchema,
      messages: [hash_including(role: 'system', content: /Spanish/), { role: 'user', content: "Hello\u0001 world" }]
    ).and_return(message: { 'translation' => "Hola\u0001 mundo" })

    expect(service.perform).to eq(message: 'Hola mundo')
    expect(Captain::Llm::MessageTranslationSchema.fields).to eq([:translation])
  end

  it 'preserves API errors' do
    allow(service).to receive(:make_api_call).and_return(error: 'failed', error_code: 500)
    expect(service.perform).to eq(error: 'failed', error_code: 500)
  end

  it 'compares base language tags' do
    expect(described_class.same_language?('pt-BR', 'pt_BR')).to be(true)
    expect(described_class.same_language?('en', 'es')).to be(false)
  end
end
