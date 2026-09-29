class AddCaptainHandedOffAtToConversations < ActiveRecord::Migration[7.2]
  def change
    add_column :conversations, :captain_handed_off_at, :datetime, null: true
  end
end