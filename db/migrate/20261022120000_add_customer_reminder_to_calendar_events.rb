class AddCustomerReminderToCalendarEvents < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  PENDING = 'deleted_at IS NULL AND customer_reminder_sent_at IS NULL AND ' \
            "(customer_reminder_status IS NULL OR customer_reminder_status IN ('no_template', 'retry_1', 'retry_2'))".freeze

  def change
    add_column :calendar_events, :customer_reminder_sent_at, :datetime
    add_column :calendar_events, :customer_reminder_status, :string
    add_index :calendar_events, :start_at, name: 'index_calendar_events_on_pending_customer_reminder', where: PENDING,
                                           algorithm: :concurrently
  end
end
