# Cert Copilot — criterios y evidencia

## Cambio visible

Se agrega una certificación de integración para chat Copilot, `ResponseJob`, sugerencia contextual, propuestas de acción y el máximo de 20 llamadas de herramientas por turno. Los proveedores LLM se simulan dentro del proceso.

## Criterios verificados

- Cuota del chat: éxito consume; respuesta vacía, error y excepción liberan; cada llamada registra `AiUsageEvent` con el resultado correspondiente. Evidencia: `spec/integration/ai_certification/copilot_spec.rb:39-101`; implementación `enterprise/app/services/captain/copilot/chat_service.rb:47-66`.
- Mensajes persistidos: el primer mensaje y los siguientes pasan por `ResponseJob` sin duplicar el mensaje del hilo. Evidencia: `spec/integration/ai_certification/copilot_spec.rb:104-130`; `enterprise/app/jobs/captain/copilot/response_job.rb:4-25`.
- Sugerencia contextual: éxito consume y registra `ok`; error libera y registra `error`. Evidencia: `spec/integration/ai_certification/copilot_spec.rb:153-206`; `enterprise/app/services/captain/copilot/reply_suggestion_usage.rb:4-44`.
- JSON mal formado o duplicado: fallback al texto y conservación del primer objeto. Evidencia: `spec/enterprise/helpers/captain/chat_response_helper_spec.rb:21-36`; `enterprise/app/helpers/captain/chat_response_helper.rb:16-34`.
- Propuestas: schema `oneOf` por acción, errores accionables, sin ejecutar al proponer, idempotencia y aprobación mediante tarjeta. Evidencia: `enterprise/app/services/captain/tools/copilot/propose_action_service.rb:10-44`, `enterprise/app/services/captain/copilot/action_item_service.rb:12-45`, `spec/enterprise/services/captain/copilot/action_item_service_spec.rb:38-53,125-137`.
- Afirmaciones: Copilot no afirma una propuesta no persistida; el prompt remite la aprobación a la tarjeta. Evidencia: `enterprise/app/services/captain/copilot/proposal_claim_validator.rb:20-43`; `spec/enterprise/services/captain/copilot/chat_service_tool_registration_spec.rb:30-50`.
- Límite por turno: acepta 20 llamadas de herramientas y rechaza la 21. Evidencia: `enterprise/app/services/captain/copilot/tool_call_limiter.rb:1-18`; `spec/integration/ai_certification/copilot_spec.rb:135-138`.
- Concurrencia: con un solo crédito Copilot, solo una de dos reservas pasa. Evidencia: `spec/integration/ai_certification/copilot_spec.rb:209-239`.

## Verificación

- RSpec, siete archivos del alcance: **88 examples, 0 failures**.
- CSV del spec: **11 contratos Copilot, 11 PASS**.
- RuboCop sobre el spec nuevo: **0 offenses**.
- `git diff --check`: limpio.
- Base de test aislada `chatwoot_test_copilot`, cargada con `db/schema.rb`; `u08_test` estaba ocupada por la rebanada C.

Matriz completa: `docs-crm/codex/cert-copilot.md`.
