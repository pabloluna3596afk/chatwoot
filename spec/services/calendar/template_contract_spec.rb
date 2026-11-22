require 'rails_helper'

template_languages = %w[es en].freeze
template_functions = %w[confirmation cancellation reminder].freeze

RSpec.describe Calendar::TemplateContract do
  let(:template) do
    { 'id' => 'remote', 'name' => 'chosen_version', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'parameter_format' => 'NAMED', 'components' => [
        { 'type' => 'BODY', 'text' => '{{nombre}}: {{cita}} el {{fecha}} a las {{hora}}' },
        { 'type' => 'BUTTONS', 'buttons' => %w[Confirmar Reagendar Cancelar].map { |label| { 'type' => 'QUICK_REPLY', 'text' => label } } }
      ] }
  end
  let(:contract) { described_class.new(function: :confirmation, language: 'es', template: template) }

  template_languages.each do |language|
    template_functions.each do |function|
      it "accepts the #{function} contract in #{language} without requiring the default name or copy" do
        definition = Calendar::TemplateDefinitions.definition(function, language)
        template['language'] = language
        template['components'].last['buttons'] = definition[:buttons].map { |label| { 'type' => 'QUICK_REPLY', 'text' => label } }
        candidate = described_class.new(function: function, language: language, template: template)
        expect(candidate.incompatibility).to be_nil
        expect(candidate.snapshot['actions'].size).to eq(function == 'cancellation' ? 0 : 3)
      end
    end
  end

  it 'rejects a media header whose parameters cannot be filled by appointment values' do
    template['components'] << { 'type' => 'HEADER', 'format' => 'IMAGE' }
    expect(contract.incompatibility).to eq('components')
  end

  it 'rejects variables in a header even when all body variables match' do
    template['components'] << { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Hola {{nombre}}' }
    expect(contract.incompatibility).to eq('components')
  end

  it 'rejects a missing body value' do
    template['components'].first['text'] = '{{nombre}} {{cita}} {{fecha}}'
    expect(contract.incompatibility).to eq('variables')
  end

  it 'rejects positional or unexpected body variables' do
    template['components'].first['text'] += ' {{1}}'
    expect(contract.incompatibility).to eq('variables')
  end

  it 'rejects a URL button that uses the same label as a known action' do
    template['components'].last['buttons'].first['type'] = 'URL'
    expect(contract.incompatibility).to eq('buttons')
  end

  it 'rejects a different language and a missing remote identity' do
    template['language'] = 'en'
    expect(contract.incompatibility).to eq('language')
    template['language'] = 'es'
    template.delete('id')
    expect(contract.incompatibility).to eq('remote_identity')
  end

  it 'keeps a version stable after JSONB reorders component keys or Meta omits examples' do
    original = contract.snapshot['version']
    template['components'] = template['components'].map { |component| component.to_a.reverse.to_h }
    template['components'].first['example'] = { 'body_text_named_params' => [] }
    expect(contract.snapshot['version']).to eq(original)
  end
end
