class AddSaasFieldsToPlansAndAccounts < ActiveRecord::Migration[7.2]
  def up
    add_column :plans, :max_documents, :integer, null: false, default: 10
    add_column :plans, :is_default_trial, :boolean, null: false, default: false
    add_index :plans, :is_default_trial, unique: true, where: 'is_default_trial', name: 'index_plans_on_is_default_trial'

    # Documents were incorrectly limited by storage_mb (a byte budget, not a
    # count) — backfill max_documents from the same real numbers so existing
    # plans don't regress until someone tunes them for real in SuperAdmin.
    execute 'UPDATE plans SET max_documents = storage_mb'

    add_column :accounts, :plan_started_at, :datetime
    execute 'UPDATE accounts SET plan_started_at = created_at WHERE plan_id IS NOT NULL'
  end

  def down
    remove_column :accounts, :plan_started_at
    remove_index :plans, name: 'index_plans_on_is_default_trial'
    remove_column :plans, :is_default_trial
    remove_column :plans, :max_documents
  end
end
