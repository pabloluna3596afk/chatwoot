json.payload do
  json.array! @captain_inboxes do |captain_inbox|
    json.partial! 'api/v1/models/inbox', formats: [:json], resource: captain_inbox.inbox
    json.appointments_enabled captain_inbox.appointments_enabled
  end
end

json.meta do
  json.total_count @captain_inboxes.size
  json.page 1
end
