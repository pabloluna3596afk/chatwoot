json.partial! 'api/v1/accounts/automation_rules/partials/automation_rule', formats: [:json], automation_rule: @automation_rule

# Conflicts with other rules don't block the save; the client shows them after.
json.automation_rule_warnings(@lint_warnings || []) do |warning|
  json.rule_id warning.rule_id
  json.rule_name warning.rule_name
  json.code warning.code
  json.message_key warning.message_key
  json.meta warning.meta
end
