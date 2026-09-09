json.id automation_rule.id
json.account_id automation_rule.account_id
json.name automation_rule.name
json.description automation_rule.description
json.event_name automation_rule.event_name
json.conditions automation_rule.conditions
json.actions automation_rule.actions
json.schedule automation_rule.schedule
json.created_on automation_rule.created_at.to_i
json.active automation_rule.active?
json.preset_id automation_rule.preset_id
json.enforces_business_rules automation_rule.enforces_business_rules?
json.execution_delay automation_rule.execution_delay
json.files automation_rule.file_base_data if automation_rule.files.any?
