class CreateAccountPlanUsages < ActiveRecord::Migration[7.2]
  def change
    create_table :account_plan_usages do |t|
      t.bigint :account_id, null: false
      t.bigint :plan_id
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.integer :responses_consumed, null: false, default: 0
      t.integer :documents_consumed, null: false, default: 0
      t.integer :limit_responses
      t.integer :limit_documents
      t.datetime :closed_at

      t.timestamps
    end

    add_index :account_plan_usages, [:account_id, :period_start], unique: true, name: 'index_account_plan_usages_on_account_and_period_start'
    add_index :account_plan_usages, :account_id, where: 'closed_at IS NULL', name: 'index_account_plan_usages_on_account_id_open'
    add_foreign_key :account_plan_usages, :accounts
    add_foreign_key :account_plan_usages, :plans
  end
end
