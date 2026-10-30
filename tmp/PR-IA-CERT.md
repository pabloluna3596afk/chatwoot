# Certificación IA — tercera pasada

**Estado: INCOMPLETA. No declarar CONFIRMADO.** La matriz automatizada de los 16 flujos × 14 escenarios no quedó implementada: no existen adaptadores con fixtures válidos para ejecutar los 224 casos en las entradas reales; el mock de preview cubre solo propuestas. Los briefs originales `.codex/BRIEF-IA-CERTIFICACION.md` y `.codex/BRIEF-IA-CERT-PROPUESTAS.md` no están presentes en este worktree.

## Estado Z1–Z8

| Criterio | Estado | Evidencia y brecha |
|---|---|---|
| Z1 Inventario mecánico | PARCIAL | `Llm::MeteringGuard`, `Llm::UsageContext` y el mapa de buckets existen. No se ejecutó inventario completo con `LLM_METERING_TRACE=1` sobre todos los consumidores (PDF, endpoint legacy, evaluadores, FAQ y HTTP). |
| Z2 Guardián único | PARCIAL | Los specs focales de guard y consumidores pasan dentro de la corrida de 102 ejemplos. No se ejercitó el universo de llamadas directas del inventario. |
| Z3 Entitlement central | PARCIAL | Entitlement en Copilot, tareas Captain y controller de hilos revisados; 102 specs focales pasan. Playground, V1/V2 y todos los servicios no están cubiertos por un contrato común de matriz. |
| Z4 Regla común de fallo | PARCIAL | Copilot/tareas liberan reservas ante error, respuesta vacía o excepción en pruebas focales. No se comprobó la regla para cada flujo de FAQ, embeddings, moderación y respuesta de cliente. |
| Z5 Matriz E2E | INCOMPLETA | No hay runner de datos ni spec `spec/integration` para los 224 casos base. Se conservan 3 PASS de propuestas reportados en la pasada previa (propuesta/reintento, aprobación conversacional, aprobación desde tarjeta); no se repitieron en esta sesión. |
| Z6 Hallazgos 11, 12, 13 | PARCIAL | Gate de Copilot/tareas ahora se activa en specs; se corrigió el contrato de persistencia de estados de herramienta. Sin ciclo E2E completo del primer/siguiente turno, contador legado y plan sin gate; no marcar cerrado. |
| Z7 RSpec / RuboCop / Vitest / ESLint / eager load | PARCIAL | RSpec dirigido 102 ejemplos/0 fallos; eager load 1/1; RuboCop CI 25 archivos/0 ofensas; Vitest 4/4 en UTC y 4/4 en America/Guayaquil. ESLint global: 189 errores y 810 advertencias existentes; no hay frontend en el diff. |
| Z8 Lo no verificado | DOCUMENTADO | 224 casos excluidos de certificación: 221 sin ejecución previa y 3 mediciones históricas parciales que no comparan las tres tablas. No se añaden PASS por inferencia. |

## Totales de escenarios

- Matriz total: **227** (224 combinaciones de flujos × escenarios + 3 escenarios de propuestas).
- PASS con evidencia de preview previa: **3** (no repetidos en esta sesión).
- FAIL abiertos en la matriz: **0**; 15 fallos intermedios de RSpec fueron corregidos y la corrida final focalizada quedó en 0.
- Excluidos de certificación: **224** (221 no ejecutados y 3 parciales sin deltas completos de `account_plan_usages`, `ai_usage_reservations` y `ai_usage_events`).
- No se declaró CONFIRMADO; el criterio de cero escenarios excluidos no se cumple.

## Verificaciones

- `rspec-local.sh`: 102 ejemplos, 0 fallos en los ocho specs focales de Captain/Copilot/LLM.
- `spec/rails/application_eager_load_spec.rb`: 1 ejemplo, 0 fallos.
- RuboCop CI: 25 archivos Ruby completos, 0 ofensas.
- Vitest `CopilotThinkingGroup`: 4 pruebas en UTC y 4 en America/Guayaquil.
- ESLint global directo: 189 errores y 810 advertencias; `pnpm eslint` bloqueado porque host tiene pnpm 9.15.0 y el repo requiere pnpm 10.x.
- `git diff --check`: sin errores.
- El E2E de etiqueta de la pasada previa está documentado en `docs-crm/codex/ia-certificacion.md`; no se repitió en este ciclo.
- Sin LLM real, push ni PR.
