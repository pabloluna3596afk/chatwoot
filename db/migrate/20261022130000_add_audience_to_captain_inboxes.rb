class AddAudienceToCaptainInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_inboxes, :audience_mode, :string, null: false, default: 'inherit'
    add_column :captain_inboxes, :audience_rules, :jsonb, null: false, default: {}
  end
end
