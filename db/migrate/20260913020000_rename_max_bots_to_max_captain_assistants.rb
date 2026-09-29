class RenameMaxBotsToMaxCaptainAssistants < ActiveRecord::Migration[7.2]
  def change
    rename_column :plans, :max_bots, :max_captain_assistants
  end
end
