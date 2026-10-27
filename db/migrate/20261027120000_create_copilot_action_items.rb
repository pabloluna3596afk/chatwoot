class CreateCopilotActionItems < ActiveRecord::Migration[7.2]
  def change
    create_action_items
    create_action_events
  end

  private

  def create_action_items
    create_table :copilot_action_items do |t|
      add_proposal_columns(t)
      t.timestamps
      t.index [:account_id, :user_id, :status], name: 'index_copilot_action_items_on_owner_and_status'
      t.index :idempotency_key, unique: true
    end
  end

  def add_proposal_columns(table)
    table.references :account, null: false, foreign_key: true
    table.references :user, null: false, foreign_key: true
    table.references :copilot_thread, null: false, foreign_key: true
    table.references :copilot_message, foreign_key: true
    table.string :action, null: false
    table.string :target_type, null: false
    table.bigint :target_id, null: false
    table.jsonb :payload, null: false, default: {}
    table.string :payload_hash, null: false
    table.string :status, null: false, default: 'pending'
    table.datetime :expires_at, null: false
    table.string :idempotency_key, null: false
    table.jsonb :result
    table.text :error
    table.datetime :decided_at
    table.datetime :executed_at
  end

  def create_action_events
    create_table :copilot_action_events do |t|
      t.references :item, null: false, foreign_key: { to_table: :copilot_action_items }, index: { name: 'index_copilot_action_events_on_item' }
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :event, null: false
      t.jsonb :payload_snapshot, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end
end
