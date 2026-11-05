class AiUsageEvent < ApplicationRecord
  BUCKETS = %w[captain_responses copilot internal unmapped].freeze

  belongs_to :account

  validates :bucket, inclusion: { in: BUCKETS }
  validates :feature, :model, :provider, :usage_group_id, :created_at, presence: true
  validates :status, inclusion: { in: %w[ok error] }
  validates :units, numericality: { only_integer: true, greater_than: 0 }
  validates :input_tokens, :cached_input_tokens, :output_tokens, :reasoning_tokens,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :audio_duration_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :for_month, ->(date) { where(created_at: date.all_month) }

  def self.calculate_cost(model:, input_tokens:, cached_input_tokens:, output_tokens:, at: Time.current)
    price = AiModelPrice.current_for(model, at: at)
    return 0.to_d unless price

    cached_tokens = [cached_input_tokens.to_i, input_tokens.to_i].min
    uncached_input = [input_tokens.to_i - cached_tokens, 0].max
    ((uncached_input * price.input_per_million) +
      (cached_tokens * price.cached_input_per_million) +
      (output_tokens.to_i * price.output_per_million)) / 1_000_000
  end

  def self.calculate_audio_cost(model:, duration_seconds:, at: Time.current)
    return 0.to_d if duration_seconds.nil?

    price = AiModelPrice.current_for(model, at: at)
    return 0.to_d unless price&.audio_per_minute

    BigDecimal(duration_seconds.to_s) * price.audio_per_minute / 60
  end
end
