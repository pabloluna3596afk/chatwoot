class CreateAiUsageLedger < ActiveRecord::Migration[7.2]
  MODELS = %w[
    gpt-6-luna gpt-6.1-sol gpt-5.1 gpt-5-mini gpt-5-nano gpt-5.2
    claude-haiku-4.5 claude-sonnet-4.5 gemini-3-flash gemini-3-pro
    gpt-transcribe text-embedding-3-small
  ].freeze

  def up
    create_model_prices
    create_ai_usage_events
    seed_model_prices
  end

  def down
    drop_table :ai_usage_events
    drop_table :ai_model_prices
  end

  private

  def create_model_prices
    create_table :ai_model_prices do |t|
      t.string :model, null: false
      t.decimal :input_per_million, precision: 12, scale: 8, null: false, default: 0
      t.decimal :cached_input_per_million, precision: 12, scale: 8, null: false, default: 0
      t.decimal :output_per_million, precision: 12, scale: 8, null: false, default: 0
      t.datetime :effective_from, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :ai_model_prices, [:model, :effective_from], unique: true
    add_index :ai_model_prices, [:model, :active, :effective_from], name: 'index_ai_model_prices_for_lookup'
  end

  # rubocop:disable Metrics/MethodLength
  def create_ai_usage_events
    create_table :ai_usage_events do |t|
      t.references :account, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.string :bucket, null: false
      t.string :feature, null: false
      t.string :model, null: false
      t.string :provider, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :cached_input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :reasoning_tokens, null: false, default: 0
      t.decimal :cost_usd, precision: 12, scale: 8, null: false, default: 0
      t.string :status, null: false, default: 'ok'
      t.string :error_class
      t.integer :latency_ms
      t.uuid :usage_group_id, null: false
      t.bigint :conversation_id
      t.bigint :message_id
      t.datetime :created_at, null: false
    end
    add_index :ai_usage_events, [:account_id, :created_at]
    add_index :ai_usage_events, [:account_id, :bucket, :created_at]
    add_index :ai_usage_events, :usage_group_id
    add_index :ai_usage_events, [:account_id, :conversation_id, :message_id]
  end
  # rubocop:enable Metrics/MethodLength

  def seed_model_prices
    MODELS.each { |model| insert_model_price(model) }
  end

  def insert_model_price(model)
    luna = model == 'gpt-6-luna'
    execute <<~SQL.squish
      INSERT INTO ai_model_prices
        (model, input_per_million, cached_input_per_million, output_per_million,
         effective_from, active, created_at, updated_at)
      VALUES (#{connection.quote(model)}, #{luna ? 0.10 : 0}, #{luna ? 0.10 : 0},
              #{luna ? 0.50 : 0}, '2026-01-01 00:00:00', #{luna},
              #{connection.quote(Time.current)}, #{connection.quote(Time.current)})
    SQL
  end
end
