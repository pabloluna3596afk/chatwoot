class AddStorageTrackingToAccountPlanUsages < ActiveRecord::Migration[7.2]
  def change
    add_column :account_plan_usages, :storage_consumed, :bigint, default: 0, null: false
    add_column :account_plan_usages, :limit_storage_bytes, :bigint

    # Add index for better query performance
    add_index :account_plan_usages, :storage_consumed
  end
end