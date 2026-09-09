class AddPresetIdToAutomationRules < ActiveRecord::Migration[7.1]
  def change
    add_column :automation_rules, :preset_id, :string
    add_index :automation_rules, [:account_id, :preset_id]
  end
end
