class CreateCaptainDecisions < ActiveRecord::Migration[7.2]
  def change
    create_table :captain_decisions do |t|
      decision_references(t)
      decision_attributes(t)
      decision_payload(t)
      t.timestamps
    end
    decision_indices
    decision_constraints
  end

  private

  def decision_references(table)
    table.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
    table.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
    table.references :assistant, foreign_key: { to_table: :captain_assistants, on_delete: :nullify }
    table.references :anchor_message, foreign_key: { to_table: :messages, on_delete: :nullify }
    table.references :agent_session, foreign_key: { to_table: :agent_sessions, on_delete: :nullify }
    table.references :parent_decision, foreign_key: { to_table: :captain_decisions, on_delete: :nullify }
  end

  def decision_attributes(table)
    table.integer :version, null: false, default: 1
    table.string :kind, limit: 40, null: false
    table.string :outcome, limit: 24, null: false
    table.string :origin, limit: 24, null: false
    table.string :trigger, limit: 40, null: false
    table.string :decision_key, limit: 200, null: false
    table.string :reason_code, limit: 80, null: false
    table.string :reason_locale, limit: 16, null: false
    table.text :reason_text
  end

  def decision_payload(table)
    table.jsonb :evidence, null: false, default: {}
    table.jsonb :settings_snapshot, null: false, default: {}
    table.jsonb :technical_details, null: false, default: {}
    table.timestamptz :occurred_at, null: false
    table.timestamptz :due_at
  end

  def decision_indices
    add_index :captain_decisions, [:account_id, :decision_key], unique: true
    add_index :captain_decisions, [:account_id, :anchor_message_id]
    add_index :captain_decisions, [:account_id, :conversation_id, :occurred_at, :id], name: 'index_captain_decisions_on_conversation_timeline'
    add_index :captain_decisions, :occurred_at
  end

  def decision_constraints
    %w[evidence settings_snapshot technical_details].each do |column|
      add_check_constraint :captain_decisions, "jsonb_typeof(#{column}) = 'object'", name: "captain_decisions_#{column}_object"
    end
    add_check_constraint :captain_decisions,
                         'octet_length(evidence::text) + octet_length(settings_snapshot::text) + octet_length(technical_details::text) <= 8192',
                         name: 'captain_decisions_payload_size'
    add_check_constraint :captain_decisions, 'char_length(reason_text) <= 500', name: 'captain_decisions_reason_length'
  end
end
