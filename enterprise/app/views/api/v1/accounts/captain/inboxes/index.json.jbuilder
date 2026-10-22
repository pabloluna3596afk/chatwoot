json.payload do
  json.array! @captain_inboxes do |captain_inbox|
    json.partial! 'api/v1/models/inbox', formats: [:json], resource: captain_inbox.inbox
    json.appointments_enabled captain_inbox.appointments_enabled
    json.audience_mode captain_inbox.audience_mode
    json.audience_rules captain_inbox.audience_rules
  end
end

json.meta do
  json.total_count @captain_inboxes.size
  json.page 1
end
