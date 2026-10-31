# CertificaciÃ³n Copilot â€” rebanada B

## Alcance y resultado

Se certificaron el chat de Copilot por `ChatService` y `ResponseJob`, la sugerencia contextual de respuesta, las propuestas `propose_action` y el lÃ­mite de herramientas por turno. Los clientes LLM se sustituyeron en proceso; no se hicieron llamadas reales.

La suite final terminÃ³ con **88 ejemplos, 88 PASS, 0 FAIL y 0 excluidos**. El spec de esta rebanada imprime al finalizar un CSV con 11 contratos Copilot; los 11 quedaron en PASS. La ejecuciÃ³n final usÃ³ `chatwoot_test_copilot`, una base de test aislada cargada con `db/schema.rb`, porque `u08_test` estuvo ocupada por la suite de la rebanada C.

## Matriz de escenarios

| Flujo | Escenario | Esperado | Real | Estado |
|---|---|---|---|---|
| Chat | Ã‰xito | +1 en Copilot; recibo consumido; evento `ok` | +1 en `copilot_responses_consumed`; recibo cerrado; un `AiUsageEvent` `ok` | PASS |
| Chat | Error del proveedor | Sin consumo; recibo liberado; evento `error` | 0 consumos; recibo con `released_at`; evento `error` | PASS |
| Chat | ExcepciÃ³n durante la llamada | Sin consumo; recibo liberado; excepciÃ³n propagada y evento `error` | 0 consumos; recibo liberado; `Timeout::Error` propagada; evento `error` | PASS |
| Chat | Respuesta vacÃ­a | Sin consumo; recibo liberado; llamada registrada | 0 consumos; recibo liberado; evento `ok` | PASS |
| Chat | JSON mal formado / JSON duplicado | Fallback de texto para JSON invÃ¡lido; conservar solo el primer objeto repetido | Parser devuelve el texto en fallback y el primer objeto en duplicados | PASS |
| Chat | Bolsa compartida (`NULL`) agotada | 429 sin llamada al proveedor cuando se agota el pool de respuestas compartido | El spec bloquea la llamada al proveedor con `responses_consumed = 100` | PASS |
| Chat | Feature desactivada | 403 sin llamada al proveedor ni evento | 403; no se invocÃ³ el proveedor; cero eventos | PASS |
| Chat | Reintento tras fallo | El fallo libera; el reintento exitoso consume una vez | Specs de servicio verifican un Ãºnico crÃ©dito despuÃ©s del retry | PASS |
| Chat | Concurrencia con un crÃ©dito | Solo una reserva pasa | Dos reservas simultÃ¡neas: una aceptada y contador en 1 | PASS |
| ResponseJob | Primer mensaje y mensajes siguientes | Usa el historial persistido y una reserva/evento por turno, sin duplicar la entrada | Dos turnos; 2 crÃ©ditos, 2 eventos `ok`, cada servicio recibe el mensaje actual una vez | PASS |
| Sugerencia Copilot | Ã‰xito y error del proveedor | Ã‰xito consume y registra `ok`; error libera y registra `error` | Ã‰xito: +1, recibo cerrado, evento `ok`; error: 0, recibo liberado, evento `error` | PASS |
| Propuestas | Esquema por acciÃ³n y error accionable | AcciÃ³n restringida por esquema; errores claros; propuesta invÃ¡lida no se persiste | `oneOf` por acciÃ³n; acciÃ³n desconocida devuelve `Unsupported action`; no crea item | PASS |
| Propuestas | Idempotencia y aprobaciÃ³n | Repetir no duplica; proponer no ejecuta; aprobar en la tarjeta ejecuta una vez | Item pendiente hasta `decide(approve)`; repeticiÃ³n idÃ©ntica reutiliza el item; ejecuciÃ³n idempotente | PASS |
| Propuestas | Afirmar una propuesta inexistente | No declarar propuesta sin `proposal_id` persistido; aprobaciÃ³n solo desde la tarjeta | El validador corrige el texto; el prompt indica aprobar con la tarjeta | PASS |
| Herramientas | 20/21 llamadas por turno | Permitir 20; rechazar la 21 | El limiter permite 20 y rechaza la siguiente | PASS |

Las propuestas se incluyen en el consumo/evento del turno de chat que las contiene; no reservan un crÃ©dito LLM adicional.

## CSV del spec

```csv
scenario,result
Captain::Copilot::ChatService chat turn reservation returns the disabled feature status before making a provider request,PASS
Captain::Copilot::ChatService chat turn reservation releases the reservation and records an error when the provider raises,PASS
Captain::Copilot::ChatService chat turn reservation keeps the first and subsequent persisted user messages in one turn each,PASS
Captain::Copilot::ChatService chat turn reservation behaves like a Copilot turn reservation charges one Copilot call only after a successful response,PASS
Captain::Copilot::ChatService chat turn reservation behaves like a Copilot turn reservation charges one Copilot call only after a successful response,PASS
Captain::Copilot::ChatService chat turn reservation when the provider returns an error behaves like a Copilot turn reservation charges one Copilot call only after a successful response,PASS
Captain::Copilot::ChatService tool calls and proposals allows twenty tool calls and rejects the twenty-first within one turn,PASS
Captain::Copilot::ChatService tool calls and proposals limits proposals and returns actionable errors without executing an action,PASS
Captain::Copilot::ChatService reply suggestion billing consumes one credit and records the successful provider event,PASS
Captain::Copilot::ChatService reply suggestion billing releases the failed reservation and records the provider error,PASS
Captain::Copilot::ChatService concurrent Copilot reservations admits only one reservation for the last Copilot credit,PASS
```

## Evidencia

- InstrumentaciÃ³n de chat, reserva y control de errores: `enterprise/app/services/captain/copilot/chat_service.rb:47,196`; recibo por turno: `enterprise/app/services/captain/copilot/chat_service.rb:50-66`.
- Job e historial persistido: `enterprise/app/jobs/captain/copilot/response_job.rb:4-25`.
- Sugerencia contextual, reserva y evento: `enterprise/app/services/captain/copilot/reply_suggestion_usage.rb:4-44`; resultado persistido: `enterprise/app/services/captain/copilot/reply_suggestion_service.rb:24-52`.
- Parser JSON: `enterprise/app/helpers/captain/chat_response_helper.rb:16-34`; contratos: `spec/enterprise/helpers/captain/chat_response_helper_spec.rb:21-36`.
- Herramientas por turno: `enterprise/app/services/captain/copilot/tool_call_limiter.rb:1-18`; contrato: `spec/integration/ai_certification/copilot_spec.rb:135-138`.
- Propuestas por acciÃ³n y validaciÃ³n: `enterprise/app/services/captain/tools/copilot/propose_action_service.rb:10-44`; idempotencia/aprobaciÃ³n: `enterprise/app/services/captain/copilot/action_item_service.rb:12-45`.
- No afirmar propuestas inexistentes ni aprobar en el chat: `enterprise/app/services/captain/copilot/proposal_claim_validator.rb:20-43`; prompt y contrato: `enterprise/app/services/captain/copilot/chat_service.rb:89-92`, `spec/enterprise/services/captain/copilot/chat_service_tool_registration_spec.rb:30-50`.
- Spec de certificaciÃ³n: `spec/integration/ai_certification/copilot_spec.rb:1-243`.

## Comandos ejecutados

- RSpec: 7 archivos del alcance, `88 examples, 0 failures`.
- RuboCop: `spec/integration/ai_certification/copilot_spec.rb`, sin ofensas.
- `git diff --check`, sin errores.
