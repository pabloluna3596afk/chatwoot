class RenameCaptainPlansToPlans < ActiveRecord::Migration[7.2]
  def change
    # Postgres auto-renames indexes/sequences tied to a renamed table or column
    # (as long as they still have their default Rails-generated name), so no
    # explicit rename_index calls are needed here.
    rename_table :captain_plans, :plans
    rename_column :accounts, :captain_plan_id, :plan_id

    add_column :plans, :max_inboxes, :integer, null: false, default: 1
    add_column :plans, :max_emails_per_day, :integer, null: false, default: 0
  end
end
