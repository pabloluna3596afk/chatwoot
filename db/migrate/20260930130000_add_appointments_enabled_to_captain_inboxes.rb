class AddAppointmentsEnabledToCaptainInboxes < ActiveRecord::Migration[7.1]
  def change
    # Per-channel switch for appointments; it only matters while the assistant has appointments on.
    add_column :captain_inboxes, :appointments_enabled, :boolean, null: false, default: true
  end
end
