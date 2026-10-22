json.partial! 'api/v1/models/inbox', formats: [:json], resource: @captain_inbox.inbox
json.appointments_enabled @captain_inbox.appointments_enabled
json.audience_mode @captain_inbox.audience_mode
json.audience_rules @captain_inbox.audience_rules
