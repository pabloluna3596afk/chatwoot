module Llm::UnitCosts
  module_function

  COSTS = YAML.safe_load_file(Rails.root.join('config/ai_units.yml')).freeze

  def fetch(*keys)
    keys.reduce(COSTS) { |config, key| config.fetch(key.to_s) }
  end

  def text_units(characters)
    [(characters.to_f / fetch(:text, :characters_per_chunk)).ceil, 1].max * fetch(:text, :units_per_chunk)
  end

  def audio_units(seconds)
    [(seconds.to_f / fetch(:audio, :seconds_per_minute)).ceil, 1].max * fetch(:audio, :units_per_minute)
  end
end
