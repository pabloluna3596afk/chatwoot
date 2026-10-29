class AiModelPrice < ApplicationRecord
  validates :model, :effective_from, presence: true
  validates :model, uniqueness: { scope: :effective_from }
  validates :input_per_million, :cached_input_per_million, :output_per_million,
            numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  def self.current_for(model, at: Time.current)
    active.where(model: model).where('effective_from <= ?', at).order(effective_from: :desc).first
  end

  def self.seed_defaults!
    models = YAML.load_file(Rails.root.join('config/llm.yml')).fetch('models').keys
    models.each do |model|
      known_price = model == 'gpt-6-luna' ? [0.10, 0.10, 0.50] : [0, 0, 0]
      find_or_create_by!(model: model, effective_from: Time.zone.parse('2026-01-01')) do |price|
        price.input_per_million, price.cached_input_per_million, price.output_per_million = known_price
        price.active = %w[gpt-6-luna gpt-6.1-sol].include?(model)
      end
    end
  end
end
