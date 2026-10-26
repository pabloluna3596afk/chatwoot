# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::Models do
  describe '.providers' do
    it 'loads provider metadata from the config' do
      expect(described_class.providers).to include(
        'openai' => include('display_name' => 'OpenAI')
      )
    end
  end

  describe '.features' do
    it 'keeps every feature default in the allowed model list' do
      described_class.features.each do |feature_key, config|
        expect(config['models']).to include(config['default']), "#{feature_key} default model must be allowed"
      end
    end

    it 'references existing models from every feature' do
      described_class.features.each do |feature_key, config|
        missing_models = config['models'].reject { |model_name| described_class.models.key?(model_name) }

        expect(missing_models).to be_empty, "#{feature_key} references missing models: #{missing_models.join(', ')}"
      end
    end

    it 'routes each FAQ operation independently' do
      expect(described_class.default_model_for('document_faq_generation')).to eq('gpt-6-luna')
      expect(described_class.default_model_for('conversation_faq_generation')).to eq('gpt-5.2')
      expect(described_class.default_model_for('conversation_faq_matching')).to eq('gpt-6-luna')
    end

    it 'offers only supported OpenAI models for conversation completion' do
      expect(described_class.models_for('conversation_completion')).to eq(
        %w[gpt-6-luna gpt-5-mini gpt-5.1 gpt-5.2]
      )
    end

    it 'does not offer retired models in any feature selector' do
      retired_models = %w[gpt-4.1 gpt-4.1-mini gpt-4.1-nano gpt-4o-mini-transcribe whisper-1]

      expect(described_class.models.keys).not_to include(*retired_models)
      expect(described_class.features.values.flat_map { |feature| feature['models'] }).not_to include(*retired_models)
    end
  end

  describe '.models' do
    it 'references existing providers from every model' do
      missing_providers = described_class.models.filter_map do |model_name, config|
        provider = config['provider']
        next if described_class.providers.key?(provider)

        "#{model_name}: #{provider}"
      end

      expect(missing_providers).to be_empty
    end
  end

  describe '.temperature_for' do
    it 'returns the requested temperature when the model supports it' do
      expect(described_class.temperature_for('gpt-6-luna', 0.2)).to eq(0.2)
    end

    it 'omits temperature when the model does not support it' do
      allow(described_class).to receive(:model_config).with('gpt-5.2').and_return('temperature' => false)

      expect(described_class.temperature_for('gpt-5.2', 0.2)).to be_nil
    end

    it 'uses RubyLLM model metadata when config/llm.yml has no override' do
      model = instance_double(RubyLLM::Model, metadata: { temperature: false })
      allow(described_class).to receive(:model_config).with('gpt-5.2').and_return({})
      allow(RubyLLM.models).to receive(:find).with('gpt-5.2').and_return(model)

      expect(described_class.temperature_for('gpt-5.2', 0.2)).to be_nil
    end
  end

  describe '.feature_config' do
    it 'returns model metadata for a feature' do
      config = described_class.feature_config('editor')

      expect(config[:default]).to eq('gpt-6-luna')
      expect(config[:models].first).to include(
        id: 'gpt-6-luna',
        display_name: 'GPT-6 Luna',
        provider: 'openai',
        credit_multiplier: 1
      )
    end
  end
end
