json.array! @plans do |plan|
  json.extract! plan, :id, :slug, :name, :display_order, :feature_keys
  # Descriptions are withheld until existing promotional copy is reviewed.
  json.description nil
  json.state plan.catalog_state
  json.limits do
    json.monthly_responses plan.limit(:monthly_messages)
    json.copilot_responses plan.limit(:captain_copilot_responses)
    json.internal_ai_calls plan.limit(:captain_internal_calls)
    json.storage_bytes plan.limit(:storage_mb)&.megabytes
    json.assistants plan.limit(:max_captain_assistants)
    json.users plan.limit(:max_human_agents)
    json.inboxes plan.limit(:max_inboxes)
    json.emails_per_day plan.limit(:max_emails_per_day)
    json.tests_per_day plan.limit(:captain_daily_tests)
    json.trial_days plan.limit(:trial_days)
    json.trial_responses plan.limit(:trial_messages)
  end
end
