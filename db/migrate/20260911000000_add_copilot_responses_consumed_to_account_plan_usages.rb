class AddCopilotResponsesConsumedToAccountPlanUsages < ActiveRecord::Migration[7.2]
  def change
    add_column :account_plan_usages, :copilot_responses_consumed, :integer, default: 0, null: false
  end
end