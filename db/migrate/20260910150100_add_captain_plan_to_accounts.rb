class AddCaptainPlanToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_reference :accounts, :captain_plan, foreign_key: true, index: true, null: true
  end
end
