class AddCascadeToAccountPlanUsagesAccountFk < ActiveRecord::Migration[7.2]
  def up
    remove_foreign_key :account_plan_usages, :accounts
    add_foreign_key :account_plan_usages, :accounts, on_delete: :cascade
  end

  def down
    remove_foreign_key :account_plan_usages, :accounts
    add_foreign_key :account_plan_usages, :accounts
  end
end