class AddEnforcesBusinessRulesToAutomationRules < ActiveRecord::Migration[7.1]
  def change
    # Defaults to false so no existing automation changes behavior the moment
    # this ships — every automation keeps bypassing guards exactly as before
    # until an admin deliberately turns this on for a specific rule. Matches
    # how mature automation platforms roll out stricter enforcement: opt-in
    # per item, not a blanket flip that can silently break something live.
    add_column :automation_rules, :enforces_business_rules, :boolean, default: false, null: false
  end
end
