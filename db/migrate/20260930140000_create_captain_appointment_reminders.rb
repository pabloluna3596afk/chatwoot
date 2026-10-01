class CreateCaptainAppointmentReminders < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_appointment_reminders do |t|
      t.references :account, null: false, index: true
      t.references :calendar_event, null: false, index: false
      t.references :captain_assistant, null: false, index: false
      t.references :conversation, null: false, index: false
      t.string :kind, null: false
      t.datetime :scheduled_at, null: false
      t.string :status, null: false, default: 'pending'
      t.string :skipped_reason
      t.datetime :sent_at
      t.timestamps
    end

    add_index :captain_appointment_reminders, [:calendar_event_id, :kind], unique: true,
                                                                            name: 'index_captain_reminders_on_event_and_kind'
    add_index :captain_appointment_reminders, [:status, :scheduled_at], name: 'index_captain_reminders_on_status_and_scheduled_at'
  end
end
