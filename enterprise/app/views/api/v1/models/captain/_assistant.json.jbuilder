json.account_id resource.account_id
json.avatar_url resource.avatar_or_default_url
json.config resource.config.merge(
  'auto_resolve_mode' => resource.auto_resolve_mode,
  'auto_resolve_after' => resource.inactivity_threshold_minutes,
  'send_inactivity_resolution_message' => resource.send_inactivity_resolution_message?,
  'appointments' => resource.appointments.to_h,
  'followup' => resource.followup.to_h,
  'allow_paid_templates' => resource.allow_paid_templates?
)
json.created_at resource.created_at.to_i
json.description resource.description
json.guardrails resource.guardrails
json.id resource.id
json.name resource.name
json.response_guidelines resource.response_guidelines
json.updated_at resource.updated_at.to_i
