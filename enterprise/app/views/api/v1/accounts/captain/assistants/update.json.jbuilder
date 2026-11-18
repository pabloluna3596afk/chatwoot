json.partial! 'api/v1/models/captain/assistant', formats: [:json], resource: @assistant
json.paused_reason @assistant.paused_reason
json.envios Captain::Messaging::AssistantPayload.new(@assistant).as_json
json.activation_notices @activation_notices if @activation_notices.present?
