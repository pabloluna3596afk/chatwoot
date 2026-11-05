class AddUnitsToAiUsageEvents < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_usage_events, :units, :integer, null: false, default: 1
  end
end
