class AddWarningFlagsToAccountPlanUsages < ActiveRecord::Migration[7.2]
  def change
    add_column :account_plan_usages, :warned_at_80_percent, :boolean, default: false, null: false
    add_column :account_plan_usages, :warned_at_100_percent, :boolean, default: false, null: false
  end
end