class AddBookingSourceToCalendarEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :calendar_events, :booking_source, :string, default: 'manual', null: false
  end
end
