class AddActiveToAgentBots < ActiveRecord::Migration[7.1]
  def change
    add_column :agent_bots, :active, :boolean, default: true, null: false
  end
end
