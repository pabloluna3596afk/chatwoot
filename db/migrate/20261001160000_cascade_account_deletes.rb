# Deleting an account failed with PG::ForeignKeyViolation: the tables the fork added (task templates and tasks,
# internal conversations, flows, calendars...) reference accounts with a plain foreign key, and the models delete
# their rows with dependent: :destroy_async, which runs AFTER the account row is gone. Every account has at least its
# seeded task templates, so no account could be deleted. The database now deletes (or detaches) those rows itself.
class CascadeAccountDeletes < ActiveRecord::Migration[7.2]
  # [table, referenced table, extra options, on_delete]
  FOREIGN_KEYS = [
    # accounts -> the rows of the account
    [:calendar_connection_calendars, :accounts, {}, :cascade],
    [:calendar_connections, :accounts, {}, :cascade],
    [:calendar_event_activities, :accounts, {}, :cascade],
    [:calendar_events, :accounts, {}, :cascade],
    [:campaign_recipients, :accounts, {}, :cascade],
    [:flow_runs, :accounts, {}, :cascade],
    [:flows, :accounts, {}, :cascade],
    [:internal_conversations, :accounts, {}, :cascade],
    [:internal_messages, :accounts, {}, :cascade],
    [:internal_tasks, :accounts, {}, :cascade],
    [:saved_report_panels, :accounts, {}, :cascade],
    [:task_templates, :accounts, {}, :cascade],
    # children of those rows, so the cascade does not stop halfway
    [:calendar_connection_calendars, :calendar_connections, {}, :cascade],
    [:calendar_event_activities, :calendar_events, {}, :cascade],
    [:calendar_events, :calendar_connections, {}, :cascade],
    [:flow_events, :flow_runs, {}, :cascade],
    [:flow_runs, :flows, {}, :cascade],
    [:internal_messages, :internal_conversations, {}, :cascade],
    [:internal_task_events, :internal_tasks, {}, :cascade],
    [:internal_tasks, :task_templates, {}, :nullify],
    [:internal_tasks, :internal_tasks, { column: :depends_on_task_id }, :nullify],
    # what the account deletion purges first (conversations, contacts) or removes with them (messages)
    [:calendar_events, :conversations, {}, :nullify],
    [:calendar_events, :contacts, {}, :nullify],
    [:flow_runs, :conversations, {}, :cascade],
    [:internal_tasks, :conversations, {}, :cascade],
    [:internal_tasks, :messages, { column: :source_message_id }, :nullify],
    [:campaign_recipients, :campaigns, {}, :cascade],
    [:campaign_recipients, :contacts, {}, :cascade]
  ].freeze

  def up
    FOREIGN_KEYS.each do |table, to_table, options, on_delete|
      remove_foreign_key table, to_table, **options
      add_foreign_key table, to_table, **options, on_delete: on_delete
    end
  end

  def down
    FOREIGN_KEYS.each do |table, to_table, options, _on_delete|
      remove_foreign_key table, to_table, **options
      add_foreign_key table, to_table, **options
    end
  end
end
