class AddScheduleToAgentBotInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :agent_bot_inboxes, :schedule_mode, :string, default: 'always', null: false

    create_table :agent_bot_inbox_working_hours do |t|
      t.references :agent_bot_inbox, null: false, foreign_key: true, index: { name: 'index_abi_working_hours_on_agent_bot_inbox_id' }
      t.integer :day_of_week, null: false
      t.integer :open_hour
      t.integer :open_minutes
      t.integer :close_hour
      t.integer :close_minutes
      t.boolean :closed_all_day, default: false
      t.boolean :open_all_day, default: false

      t.timestamps
    end
  end
end
