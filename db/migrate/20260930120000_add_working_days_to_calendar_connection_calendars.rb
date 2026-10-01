class AddWorkingDaysToCalendarConnectionCalendars < ActiveRecord::Migration[7.1]
  def change
    # Days of the week the calendar takes appointments, 0 = Sunday .. 6 = Saturday (Date#wday).
    add_column :calendar_connection_calendars, :working_days, :integer, array: true, null: false, default: [0, 1, 2, 3, 4, 5, 6]
  end
end
