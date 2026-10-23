class CreateAutomationRuleRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :automation_rule_runs do |t|
      t.references :account, null: false
      t.bigint :automation_rule_id, null: false
      t.bigint :conversation_id
      t.bigint :contact_id
      t.string :event_name
      t.string :outcome, null: false
      t.string :reason
      t.jsonb :details, default: {}, null: false
      t.datetime :created_at, null: false
    end

    add_index :automation_rule_runs, [:automation_rule_id, :created_at]
    add_index :automation_rule_runs, [:account_id, :created_at]
  end
end
