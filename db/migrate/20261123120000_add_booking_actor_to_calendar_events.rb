class AddBookingActorToCalendarEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :calendar_events, :booking_actor, :jsonb, default: {}, null: false
  end
end
