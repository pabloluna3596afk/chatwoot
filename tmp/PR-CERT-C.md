# Certificación C — asistente y fondo

Rama `cert/background`, basada en `feat/ia-certificacion`. Sin push ni PR.

## Criterios

- Toda clave de `Llm::UsageFeatureBuckets::FEATURE_BUCKETS` tiene decisión explícita: medir y limitar, solo medir o prohibir.
- Un callsite instrumentado nuevo o sin inventariar hace fallar el spec C.
- El guard se ejecuta antes del proveedor y `Llm::UnmeteredCall` no se convierte en fallback.
- Consumidores ejecutados con `LLM_METERING_TRACE=1`; sin llamadas a proveedor externo.
- Matriz de nueve flujos por diez escenarios; cada fila tiene real y motivo de exclusión.

## Evidencia

- `lib/integrations/llm_instrumentation.rb:19`: valida contexto antes de la llamada. Línea 32 preserva el error del guard; líneas 45 y 64 aplican el mismo contrato a sesiones.
- `enterprise/app/services/captain/llm/assistant_action_classifier_service.rb:41`: requiere recibo solo cuando existe período de uso y límite interno.
- `spec/integration/ai_certification/assistant_and_background_spec.rb:9`: decisiones dinámicas para las 48 bolsas; línea 90 inventario de 15 callsites; líneas 166-184 matriz CSV.
- `spec/models/ai_usage_event_spec.rb:6`: barrido de features limitado a código de producción porque specs incluyen probes inválidos deliberados.
- RuboCop CI en seis archivos completos tocados: **0 offenses**.
- RSpec focal posterior a correcciones: **98 ejemplos, 0 fallos**.
- Pase amplio inicial de consumidores: 430 ejemplos, 5 fallos que se corrigieron (puntero `.git` no válido para `git grep` en contenedor; falsos positivos del scanner de features por probes deliberados en specs; clasificador exigía recibo con límite no configurado). Las suites de consumidores del pase amplio emitieron 123 trazas en 13 features, 0 sin cuenta y 0 sin bolsa.
- El spec generó 48 filas de guard/evento, una por bolsa, y 90 filas de escenario.

## Estado de certificación

**NO CONFIRMADO.** De las 90 celdas flujo × escenario: 0 PASS, 0 FAIL y 90 EXCLUDED. Esta rebanada ejecutó el contrato mecánico compartido, pero no fixtures independientes por flujo que correlacionen cambios de bolsa, recibo y evento. La tabla completa y la razón técnica de cada fila están en `D:/DOCUMENTOS/GITHUB/chatwoot/docs-crm/codex/cert-background.md`.

Artefactos: `tmp/ai-cert-background-inventory.csv`, `tmp/ai-cert-background-scenarios.csv`, `tmp/ai-cert-background-consumer-trace-broad.csv`.
