json.array! @plans do |plan|
  json.extract! plan, :id, :slug, :name, :display_order, :feature_keys
  # Descriptions are withheld until existing promotional copy is reviewed.
  json.description nil
  json.state plan.catalog_state
  json.limits do
    json.monthly_responses plan.monthly_messages
    json.copilot_responses plan.captain_copilot_responses
    json.internal_ai_calls plan.captain_internal_calls
    json.storage_bytes plan.storage_mb.megabytes
    json.assistants plan.max_captain_assistants
    json.users plan.max_human_agents
    json.inboxes plan.max_inboxes
    json.emails_per_day plan.max_emails_per_day
    json.tests_per_day plan.captain_daily_tests
    json.trial_days plan.trial_days
    json.trial_responses plan.trial_messages
  end
end
