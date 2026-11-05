class AddAudioPricingToAiUsage < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_model_prices, :audio_per_minute, :decimal, precision: 12, scale: 8
    add_column :ai_usage_events, :audio_duration_seconds, :decimal, precision: 12, scale: 3
  end
end
