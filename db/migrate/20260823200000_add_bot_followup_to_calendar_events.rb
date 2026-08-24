class AddBotFollowupToCalendarEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :calendar_events, :bot_followup_policy, :jsonb, default: {}, null: false
    add_column :calendar_events, :appointment_status, :string, default: 'none', null: false
    add_column :calendar_connection_calendars, :default_bot_followup_policy, :jsonb, default: {}, null: false
  end
end
