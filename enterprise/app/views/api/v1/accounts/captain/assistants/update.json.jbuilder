json.partial! 'api/v1/models/captain/assistant', formats: [:json], resource: @assistant, with_capabilities: true
json.paused_reason @assistant.paused_reason
