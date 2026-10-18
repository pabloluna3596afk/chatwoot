class AddCaptainDailyTestsToPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :plans, :captain_daily_tests, :integer, default: 0, null: false
  end
end
