class AddCaptainAiUsageBags < ActiveRecord::Migration[7.2]
  def change
    add_column :plans, :captain_copilot_responses, :integer
    add_column :plans, :captain_internal_calls, :integer
    add_column :account_plan_usages, :internal_calls_consumed, :integer, default: 0, null: false
    add_column :account_plan_usages, :limit_copilot_responses, :integer
    add_column :account_plan_usages, :limit_internal_calls, :integer
  end
end
