json.partial! 'api/v1/models/captain/assistant', formats: [:json], resource: @assistant
json.envios Captain::Messaging::AssistantPayload.new(@assistant).as_json
