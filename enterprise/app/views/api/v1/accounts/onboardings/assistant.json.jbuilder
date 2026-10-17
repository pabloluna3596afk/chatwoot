if @assistant
  json.assistant do
    json.partial! 'api/v1/models/captain/assistant', resource: @assistant
    json.paused_reason @assistant.paused_reason
    json.inbox_ids @assistant.captain_inboxes.pluck(:inbox_id)
  end
else
  json.assistant nil
end
