class AiUsageEvent < ApplicationRecord
  BUCKETS = %w[captain_responses copilot internal unmapped].freeze

  belongs_to :account

  validates :bucket, inclusion: { in: BUCKETS }
  validates :feature, :model, :provider, :usage_group_id, :created_at, presence: true
  validates :status, inclusion: { in: %w[ok error] }
  validates :input_tokens, :cached_input_tokens, :output_tokens, :reasoning_tokens,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

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
end
