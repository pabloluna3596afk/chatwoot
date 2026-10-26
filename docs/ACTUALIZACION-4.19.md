# Actualización de ChatHub a Chatwoot 4.19.1

## Alcance integrado

El historial de esta rama contiene estos PR propios:

- **#247** — fixes de seguridad y aislamiento de datos; cifrado de credenciales de custom tools.
- **#248** — actualización de Node para la herramienta de build.
- **#249** — reconciliación del esquema y del flujo de migraciones del fork.
- **#250** — campañas WhatsApp one-off por lotes, recipients y recuperación.
- **#251** — tools de Captain con alcance por assistant.
- **#252** — ajustes a modelos y contactos.
- **#253** — herramientas de email para Captain.
- **#254** — ventana configurable de búsqueda.
- **#255** — actualización de RubyLLM.
- **#256** — correcciones del Help Center.
- **#257** — mejoras de rendimiento.
- **#258** — cambios de pantallas upstream seleccionados.
- **#259** — traducción automática en backend.
- **#260** — enforcement de MFA por cuenta.
- **#261** — specs del backend de traducción.
- **#262** — actualización de dependencias aprobadas.
- **#263** — nombres de conectores.
- **#264** — límites de uso de Captain para Copilot e invocaciones internas.
- **#265** — UI de traducción automática: ajustes por cuenta y solicitudes/renderizado en el dashboard. El merge aparece ahora en `origin/develop`, pero este branch de cierre se creó sobre #264 y no incorpora esos tres commits posteriores.

## Exclusiones intencionales

- **Twilio Voice y push de voz móvil:** el producto no ofrece este flujo; no habilitar ni ejecutar migraciones que activen voz para todas las cuentas.
- **Copilot approval/durable y takeover:** el contrato actual de Captain/Panel AI no incluye este workflow; requiere decisión de producto.
- **Monitores de Captain:** se difieren porque requieren revisar cuotas, permisos y comportamiento de automatizaciones.
- **Anuncios upstream:** se mantienen fuera del producto por decisión de producto; no ejecutar backfills de anuncios.
- **Billing upstream de Stripe/Shopify:** ChatHub usa su propio modelo de planes y uso, no la facturación SaaS upstream.
- **Layouts CRM:** conservar los layouts propios del fork.
- **Dialogflow legado:** quedan referencias históricas en locales y un mailer, pero no se expone como integración activa en la configuración actual.

## Configuración y activación

- `SEARCH_TIME_RANGE_LIMIT_DAYS` fija la ventana máxima de búsqueda; si no se define son 90 días y debe ser un entero positivo ([lib/limits.rb:17-23](../lib/limits.rb:17)).
- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` y `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` configuran el cifrado de Active Record y de credenciales de custom tools ([config/application.rb:76-79](../config/application.rb:76)); las tres deben estar presentes para que MFA se considere disponible ([config/application.rb:102-113](../config/application.rb:102)). Mantenerlas estables y respaldadas en Rails y Sidekiq; no rotarlas sin un plan de recifrado y recuperación.
- Captain toma API key, modelo y endpoint opcional de Installation Config ([config/installation_config.yml:195-205](../config/installation_config.yml:195)). El modelo predeterminado documentado es `gpt-6-luna`; endpoint predeterminado `https://api.openai.com/` ([config/installation_config.yml:200-206](../config/installation_config.yml:200), [config/llm.yml:74-87](../config/llm.yml:74)).
- `auto_translate` está deshabilitado por defecto ([config/features.yml:440-443](../config/features.yml:440)). Para una cuenta piloto, habilitar el feature premium, seleccionar un proveedor disponible y activar el ajuste `auto_translate`; el runtime exige esas tres condiciones ([enterprise/app/models/enterprise/account.rb:67-79](../enterprise/app/models/enterprise/account.rb:67)).
- `enforce_mfa` no se activa por defecto: el ajuste está vacío/false hasta que un administrador lo habilite ([app/models/account.rb:70-73](../app/models/account.rb:70)). Configurar antes las tres claves de cifrado y comprobar MFA activo ([config/application.rb:102-113](../config/application.rb:102)); luego activarlo por cuenta desde Seguridad. Google OAuth y SAML se excluyen del reto local ([app/controllers/concerns/mfa_enforcement_guard.rb:8-9](../app/controllers/concerns/mfa_enforcement_guard.rb:8)).
- Las bolsas `captain_copilot_responses` y `captain_internal_calls` en planes, así como sus límites por cuenta, no tienen default SQL y comienzan en `NULL`; se pueden fijar en el plan para imponer límites ([db/migrate/20261026120000_add_captain_ai_usage_bags.rb:3-7](../db/migrate/20261026120000_add_captain_ai_usage_bags.rb:3), [db/schema.rb:49-50](../db/schema.rb:49), [db/schema.rb:1668-1669](../db/schema.rb:1668)). `internal_calls_consumed` inicia en cero ([db/schema.rb:48](../db/schema.rb:48)).

## Migraciones

Las migraciones de esta línea de actualización que requieren atención son:

| Versión | Uso |
|---|---|
| `20260907092035`, `20260907092039` | Asociar y backfill de custom tools por assistant. |
| `20260917000000` | Versión de confianza de dispositivo; es un control de dispositivo separado del MFA TOTP. |
| `20260924100000`, `20261009081158` | Headers y settings de custom tools. |
| `20261008090132` | Backfill de credenciales cifradas de custom tools. Verificar claves y backup antes de correrlo. |
| `20261016080629` | Recuperación de campañas WhatsApp. |
| `20261026120000` | Límites de uso de IA de Captain. |

La presencia de un archivo en el repo no confirma que una base de datos ya lo aplicó. Antes y después del despliegue, revisar `bundle exec rails db:migrate:status` y comparar esos timestamps con `schema_migrations` en la base del entorno (`SELECT version FROM schema_migrations ORDER BY version;`). No ejecutar migraciones omitidas de Voice, anuncios, Copilot approval ni billing.

## Despliegue y reversión

1. Programar ventana, confirmar acceso de recuperación y tomar backup verificado de PostgreSQL y de los volúmenes persistentes. Guardar también el digest de la imagen actual.
2. Construir y publicar desde un commit identificado. La etiqueta mutable `:develop` puede cambiar si dos builds o despliegues se solapan; serializar build/publicación/despliegue y registrar el digest exacto que se va a ejecutar.
3. Aplicar primero configuración y secretos compartidos de Rails/Sidekiq; confirmar las tres claves de cifrado antes de habilitar MFA o el backfill de credenciales.
4. Ejecutar una sola vez las migraciones requeridas, con copia reciente y monitoreo de duración/errores. No correr backfills irreversibles hasta validar las claves y el estado de los datos.
5. Desplegar Rails y Sidekiq con la misma imagen/digest, verificar health checks, login, búsqueda, una campaña de prueba controlada y las funciones de Captain acordadas. Mantener los interruptores nuevos apagados durante el canary.
6. Habilitar funciones gradualmente por cuenta. Verificar logs, errores de cifrado, colas y uso antes de ampliar.
7. Si falla la aplicación antes de una migración incompatible, volver al digest anterior. Si la migración cambió datos o esquema de manera incompatible, detener workers y restaurar el backup validado siguiendo el procedimiento de recuperación de la base; no asumir que un rollback de código deshace el backfill.
