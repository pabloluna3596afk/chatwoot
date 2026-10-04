# What the customer answered to the Google Calendar invite (needs_action, accepted, declined, tentative), read from the
# attendee's responseStatus.
class AddInvitationStatusToCalendarEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :calendar_events, :invitation_status, :string
  end
end
