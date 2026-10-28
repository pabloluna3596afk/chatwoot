class AddCreatedAtIndexToAiUsageEvents < ActiveRecord::Migration[7.2]
  def change
    add_index :ai_usage_events, :created_at
  end
end
