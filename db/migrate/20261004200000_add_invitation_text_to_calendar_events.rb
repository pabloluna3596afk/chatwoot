# The text of the invitation an agent wrote by hand for one appointment (nil = the account's text is used). It is kept so
# a later change of the appointment (a new time) does not replace it with the account's text.
class AddInvitationTextToCalendarEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :calendar_events, :invitation_text, :text
  end
end
