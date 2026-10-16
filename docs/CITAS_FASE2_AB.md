# Citas — entrega FASE 2 A+B

Implementado en `fix/citas-auditoria`, basado en `origin/develop`. Sin commit,
push ni PR. El archivo previo `vitest.local.config.ts` se conserva sin cambios.
No se modifican schema ni migraciones.

## Ronda de correcciones v2 (2026-10-15)

Aplicada sobre A+B en el mismo worktree, sin commit. Se revisaron las dos
capturas del PM (`cal-nuevo-normal.png` y `cal-nuevo-cancelados.png`). El PM
reportó **155/155 Vitest** para la entrega anterior; esa cifra no valida esta ronda.

| Punto del brief | Corrección | Cobertura |
|---|---|---|
| 1. Cabecera | El control de cancelados se abre con ⋮ en la fila de la leyenda, alineado al final. Cabecera `xl:flex-nowrap` (≥1280 px), selectores flexibles y fecha truncable con título completo. Abrir o activar el control no añade contenido a la cabecera ni superpone un menú sobre los días. | `CalendarViewMenus.spec.js`: control fuera del header y junto a la leyenda, contenido del header estable al abrir/activar/cerrar, filtrado y preferencia conservada al cerrar. Geometría real a 1280 px pendiente del smoke del PM. |
| 2. Grilla | Eliminado `even:bg-n-alpha-1`. Fondo uniforme de `bg-n-surface-1`, líneas horarias y verticales con `border-n-weak` solo en la grilla horaria. Sin sombreado fuera del horario ni separadores externos nuevos. | `WeekGrid.spec.js`: siete columnas, líneas horarias y ausencia de bandas alternadas. |
| 3. Carriles | Con más de un carril se oculta la hora y se retira el prefijo `Cita · ` / `Appointment · ` solo al mostrar. Nombre truncado con elipsis, datos intactos. Bloques horarios, todo el día, agenda (incluidas canceladas) y móvil tienen `title` con título completo, intervalo horario/etiqueta de todo el día y estado localizado. | `WeekGrid.spec.js`: dos/tres carriles, selección, tooltips, formato completo al ocultar cancelados y bloque de todo el día. `EventBlock.spec.js`: prefijos, truncado, título original y estado. `calendarTime.spec.js`: localización y prioridad de cancelación en tooltip. |
| 4. Estilos | Eliminadas tablas/clases dinámicas de filas y cálculo anterior de la fila de ahora. Línea actual con porcentaje; superficies, textos y bordes usan tokens `n-*`, incluido el día actual. | `WeekGrid.spec.js`, paleta de `appointmentStatus.spec.js`, revisión de código y generación PostCSS/Tailwind sin clases de geometría. Smoke oscuro en navegador pendiente. |
| 5. Horarios | `create` conserva validación; `update` exige horario solo dentro de `slot_changed?`, junto a disponibilidad. Editar nota/título/estado sin cambiar el intervalo funciona aunque hayan cambiado horas o días de atención. | `event_service_spec.rb`: nota/estado tras cambiar apertura, edición en día ahora cerrado y rechazo al cambiar solo el fin fuera del horario. `calendar_controller_spec.rb`: agente y AgentBot editan sin mover fuera de disponibilidad; se mantiene rechazo de crear/mover, ajustando fixture de día cerrado para mover realmente. |
| 6. Safelist | Eliminadas 2.881 clases de posición/duración y 24 clases de plantilla de filas. `gridRowStyle` devuelve `gridRow`; plantilla con `gridTemplateRows` inline. Precisión de un minuto y 4 rem/hora. `tailwind.config.js` queda idéntico a HEAD. | `calendarGrid.spec.js`: geometría y conversión a líneas CSS (base 1). `WeekGrid.spec.js`: inline y ausencia de clases dinámicas. Comprobación Tailwind sin safelist ni utilidades arbitrarias de fila generadas. |
| 7. Canceladas | Excepción `EventCancelled` antes de validar la transición o llamar a Google al editar una cancelada. HTTP 422 con `integration_apps.calendars.event_cancelled`: “La cita está cancelada y no se puede editar.” en ES y equivalente EN. Se conserva cancelación con motivo. | `event_service_spec.rb`: no revivir, no editar sin estado y cancelación antigua sin `deleted_at`. `calendar_controller_spec.rb`: mensaje español exacto para agente/AgentBot, con y sin estado, sin actualización remota. |
| 8. Verificación | ESLint de todo el frontend modificado/nuevo y `tailwind.config.js`: **0 errores, 17 advertencias** (5 en archivos frontend de esta ronda). `git diff --check` correcto. Compilación de ocho SFC y helpers/Tailwind correctos. | Vitest intentado con `vitest.local.config.ts`: no arranca por `spawn EPERM` de esbuild. Docker no disponible y sin Ruby local: RSpec/RuboCop y smoke real pendientes para PM/CI. |

### Archivos de esta ronda

Frontend y configuración:

- `app/javascript/dashboard/routes/dashboard/calendars/CalendarView.vue`
- `app/javascript/dashboard/routes/dashboard/calendars/AgendaSidebar.vue`
- `app/javascript/dashboard/routes/dashboard/calendars/WeekGrid.vue`
- `app/javascript/dashboard/routes/dashboard/calendars/EventBlock.vue`
- `app/javascript/dashboard/helper/calendarGrid.js`
- `app/javascript/dashboard/helper/calendarTime.js`
- `tailwind.config.js` (retirada de la safelist; sin diff final frente a HEAD)

Backend y textos:

- `lib/integrations/google_calendar/event_service.rb`
- `app/controllers/api/v1/accounts/integrations/calendar_controller.rb`
- `config/locales/en.yml`
- `config/locales/es.yml` (autorizado explícitamente por el brief)

Specs:

- `app/javascript/dashboard/routes/dashboard/calendars/specs/CalendarViewMenus.spec.js`
- `app/javascript/dashboard/routes/dashboard/calendars/specs/WeekGrid.spec.js`
- `app/javascript/dashboard/routes/dashboard/calendars/specs/EventBlock.spec.js`
- `app/javascript/dashboard/helper/specs/calendarGrid.spec.js`
- `app/javascript/dashboard/helper/specs/calendarTime.spec.js`
- `spec/lib/integrations/google_calendar/event_service_spec.rb`
- `spec/controllers/api/v1/accounts/integrations/calendar_controller_spec.rb`

Documentación: `docs/CITAS_FASE2_AB.md` y `docs/BUGS.md` (B-NEW-65).
No se modificó `vitest.local.config.ts`. Sin schema ni migraciones nuevos.
Se revisaron los consumidores Enterprise: utilizan el servicio compartido;
no fue necesario otro override para estas correcciones.

## Cambios y cobertura

| Hallazgo | Implementación | Specs |
|---|---|---|
| CIT-03 | `enforce_hours: true` por defecto en servicio y explícito en create/update del controlador. Días cerrados, apertura/cierre y error 422 localizado. | `calendar_controller_spec.rb` (agente y AgentBot, create/update, días cerrados, límites); `event_service_slots_spec.rb`; regresión `event_service_working_days_spec.rb`. |
| CIT-10 | La frontera rechaza tipos que strong params descartaría; el servicio valida valores y transiciones antes de Google. No permite crear canceladas/reprogramadas, reprogramar sin mover ni revivir canceladas. | `calendar_controller_spec.rb` (nil, vacío, número, booleano, array, objeto, desconocido y transiciones); `event_service_spec.rb`. |
| CIT-05 | PATCH cancelled delega en destroy, igual que DELETE. Motivo obligatorio, DELETE remoto con etag, estado cancelled, deleted_at, autor, liberación de clave y actividad. Estado local y motivo se guardan en una transacción. También conserva título/motivo al cancelar eventos que solo existían en Google. | `event_service_spec.rb`, `calendar_controller_spec.rb`; regresión de etag/locks y cancelación existente. |
| CIT-05 | `kept` y `discarded?` incluyen cancelaciones antiguas sin deleted_at. Ocupación local, slots, consultas de contacto, atributos, próxima cita y sender usan ese contrato. El overlay Enterprise cancela recordatorios al cambiar deleted_at o estado. | `calendar_event_spec.rb`, `event_service_slots_spec.rb`, `appointment_reminders_spec.rb`; regresión `appointment_attributes/updater_spec.rb`. |
| CIT-04 | ComboBox de estado: confirmada o pendiente. Ninguna opción de cancelación suelta ni reprogramación manual. Cambios de estado en Actividad junto con cambios de fecha/hora. | `EventModal.spec.js`, `event_service_spec.rb`. |
| CIT-01/18 | Helper puro con intersección diaria, grupos de intervalos semiabiertos y primer carril libre. Orden estable por inicio/fin/id. Carriles iguales, eventos adyacentes sin solape y escala de 30 minutos conservada. Apertura 00:00 correcta. | `calendarGrid.spec.js`, `WeekGrid.spec.js`, `EventBlock.spec.js`. |
| CIT-23/24 | Flecha localizada y fechas completas en Actividad. Paleta compartida: teal, ámbar, iris, slate y ruby; cancelación domina, conserva nombre tachado y contorno. Leyenda con tooltip. | `EventModal.spec.js`, `appointmentStatus.spec.js`, `EventBlock.spec.js`, `NextAppointmentCard.spec.js`. |
| CIT-25 | Visibilidad considera deleted y cancelled; preferencia reactiva compartida por cuenta, sin heredar la clave global. Control visible también en conversación. El control de cancelados se despliega junto a la leyenda sin alterar la cabecera ni cubrir los días. | `useCalendarCancelledVisibility.spec.js`, `appointmentStatus.spec.js`, `calendarTime.spec.js`, `WeekGrid.spec.js`; regresión `CalendarViewMenus.spec.js`. |
| CIT-16, parte necesaria para cancelación | Guardar el modal desde conversación recarga la lista y la tarjeta de próxima cita mediante el padre. | `CalendarEventsList.spec.js`, `NextAppointmentCard.spec.js`. No incluye invalidación por cambios asíncronos de Captain/Google. |

## Inventario reutilizado

- `EventService#create/update/destroy`, EventLock y BookingLock: una operación de
  cancelación y los controles de concurrencia existentes, sin un endpoint nuevo.
- `CalendarEvent#discarded?` y scope `kept`: contrato común para consumidores,
  incluido el sender existente; no se repiten comprobaciones en cada consumidor.
- Overlay `Enterprise::CalendarEvent` y Scheduler: mantienen los recordatorios
  Captain; se amplía su callback en lugar de agregar jobs paralelos.
- `Dialog`, `Input`, `TabBar`, `ComboBox`, `Button`, `Switch` y tooltip existentes.
  Se sustituyen los SelectInput nativos del modal por ComboBox.
- `appointmentStatus.js`: se amplía para colores y visibilidad, manteniendo los
  helpers de estado de cita e invitación separados.
- `calendarTime.js`: se mantienen formato, fecha y selección de slots; se retira
  `eventLayout`, que quedó sin consumidores tras cambiar la grilla.
- `useCalendarCancelledVisibility`: conserva LocalStorage y añade la cuenta a la
  clave; las distintas instancias comparten estado y reaccionan al cambio de cuenta.
- Nuevo `calendarGrid.js`: falta una operación existente que distribuya solapes.
  La geometría queda fuera de Vue y se puede probar sin navegador.

## Decisiones y límites

- Horarios estrictos para humanos, administradores, AgentBot y Captain. No se
  encontró un cliente oficial que necesite una excepción fuera de horario. Los
  clientes externos que antes dependían de ello recibirán 422 al crear o mover.
  Editar sin mover y cancelar no exigen que la cita original esté dentro del
  horario vigente.
- Al mover una cita confirmada se conserva `confirmed`, evitando que Captain
  vuelva a pedir confirmación. Una cita sin confirmar pasa a `rescheduled`
  automáticamente; ambas conservan la reprogramación en Actividad. Confirmar o
  marcar pendiente explícitamente sigue disponible en el modal.
- Nueva cita manual: confirmada inicialmente. Si el seguimiento Panel AI está
  activo y pide confirmación, empieza pendiente, conservando ese comportamiento.
- La grilla usa filas de **un minuto**, 4 rem por hora, para que reuniones cortas
  y adyacentes de Google tampoco se monten entre sí. Posición, duración y número
  de filas usan estilos inline de geometría, según la excepción expresa del brief
  v2; no hay safelist ni CSS propio. Etiquetas y slots siguen cada 30 minutos.
- La cancelación nueva elimina el evento remoto y libera el horario. Los datos
  antiguos con estado cancelled pero evento todavía activo en Google quedan
  excluidos de ocupación local y recordatorios; Google sigue siendo autoridad de
  su propia ocupación. Repararlos remotamente exige la reconciliación excluida
  por el brief. No se oculta una ocupación real del proveedor.
- Se detienen los recordatorios **Captain**. El receptor y contrato externo
  **Panel AI** permanecen fuera de alcance; no se afirma que su seguimiento
  remoto esté detenido. CIT-13/14 siguen pendientes.
- La tarjeta se refresca tras el modal de conversación. Actualizaciones remotas,
  ActionCable, respuestas fuera de orden y el resto de CIT-16/17 siguen pendientes.
- Sin cambios en zona horaria, permisos, lease, idempotencia al reprogramar,
  provisión inicial de atributos, OAuth o reconciliación. Liberar claves al
  cancelar mantiene el comportamiento existente de esa operación.
- Textos nuevos solo EN/ES según el brief, más español neutro en los errores de
  calendario existentes. Otros idiomas no se modifican.

## Validación realizada

- Ronda 3: corregidas las 18 ofensas indicadas de RuboCop mediante métodos privados y ajustes de specs, sin cambiar comportamiento; revisión manual, con RSpec/RuboCop pendientes por ausencia de Ruby.
- ESLint sobre todos los JS/Vue modificados/nuevos y `tailwind.config.js`:
  **0 errores, 17 advertencias** de claves i18n dinámicas, separadores de texto y
  el v-if raíz existente de la tarjeta.
- Compilación de script y template con `@vue/compiler-sfc` de los ocho componentes
  Vue modificados, incluido ContactPanel: correcta.
- Ejecución directa con Node de casos de geometría, cancelación y visibilidad;
  80 conjuntos densos de 20 eventos verifican conservación de eventos y ausencia
  de solapes temporales/visuales dentro de cada carril.
- Generación de utilidades mediante PostCSS/Tailwind con la configuración real:
  grillas y tokens de color presentes; sin safelist ni utilidades arbitrarias
  de posici?n/duraci?n por minuto (v2).
- JSON EN/ES y bloques YAML de calendario parseados. La lectura estricta del YAML
  español completo encontró una clave `conversations` duplicada preexistente
  fuera del módulo; no se modifica en esta tarea.
- `git diff --check`: correcto.
- **No completados:** Vitest intentado en v2 (esbuild falla al arrancar con
  `spawn EPERM`), RSpec y RuboCop (sin Ruby local ni Docker disponible), build
  Vite completo, smoke visual y E2E real.
  La compilación Vue y comprobaciones Node no sustituyen esas suites.

## Comandos pendientes para CI

Ejecutar desde este checkout. Para Ruby, usar un entorno de CI o contenedor con
las gemas de test y **una base exclusiva de pruebas** preparada desde este código;
ver `docs/TESTING.md`. No usar la base real ni `db:test:prepare` contra ella.

```sh
pnpm exec vitest run --no-coverage --no-cache \
  app/javascript/dashboard/helper/specs/calendarGrid.spec.js \
  app/javascript/dashboard/helper/specs/calendarTime.spec.js \
  app/javascript/dashboard/helper/specs/appointmentStatus.spec.js \
  app/javascript/dashboard/helper/specs/useCalendarCancelledVisibility.spec.js \
  app/javascript/dashboard/routes/dashboard/calendars/specs \
  app/javascript/dashboard/components/widgets/conversation/specs/CalendarEventsList.spec.js \
  app/javascript/dashboard/components/widgets/conversation/specs/NextAppointmentCard.spec.js

RAILS_ENV=test POSTGRES_DATABASE=chatwoot_test_citas bundle exec rspec \
  spec/lib/integrations/google_calendar \
  spec/controllers/api/v1/accounts/integrations/calendar_controller_spec.rb \
  spec/controllers/api/v1/accounts/integrations/calendar_working_days_spec.rb \
  spec/controllers/api/v1/accounts/integrations/calendar_panel_ai_spec.rb \
  spec/controllers/api/v1/accounts/integrations/calendar_invitation_spec.rb \
  spec/controllers/api/v1/accounts/contacts/calendar_events_controller_spec.rb \
  spec/models/calendar_event_spec.rb \
  spec/services/calendar/appointment_attributes/updater_spec.rb \
  spec/enterprise/services/captain/appointment_reminders_spec.rb \
  spec/enterprise/lib/captain/tools/appointment_tools_spec.rb

bundle exec rubocop --force-exclusion \
  app/controllers/api/v1/accounts/integrations/calendar_controller.rb \
  app/models/calendar_event.rb \
  app/services/calendar/appointment_attributes/updater.rb \
  enterprise/app/models/enterprise/calendar_event.rb \
  lib/integrations/google_calendar/event_service.rb \
  spec/controllers/api/v1/accounts/integrations/calendar_controller_spec.rb \
  spec/models/calendar_event_spec.rb \
  spec/lib/integrations/google_calendar/event_service_spec.rb \
  spec/lib/integrations/google_calendar/event_service_slots_spec.rb \
  spec/enterprise/services/captain/appointment_reminders_spec.rb

pnpm exec vite build
```

Smoke pendiente: claro/oscuro, móvil, dos/tres solapes y contiguos cortos, apertura
00:00, cancelar con motivo y mostrar/ocultar cancelados en todas las superficies;
dos cuentas con preferencias distintas; guardar/cancelar desde conversación sin
remontar el contacto; agente/AgentBot con disponibilidad restringida. Verificar
Google real, atributos tras procesar la cola y ausencia de recordatorios Captain.

## Archivos cambiados

38 archivos de esta entrega. `vitest.local.config.ts` es previo y no pertenece
a estos cambios.

```text
app/controllers/api/v1/accounts/integrations/calendar_controller.rb
app/javascript/dashboard/components/widgets/conversation/CalendarEventsList.vue
app/javascript/dashboard/components/widgets/conversation/NextAppointmentCard.vue
app/javascript/dashboard/components/widgets/conversation/specs/CalendarEventsList.spec.js
app/javascript/dashboard/components/widgets/conversation/specs/NextAppointmentCard.spec.js
app/javascript/dashboard/helper/appointmentStatus.js
app/javascript/dashboard/helper/calendarGrid.js
app/javascript/dashboard/helper/calendarTime.js
app/javascript/dashboard/helper/specs/appointmentStatus.spec.js
app/javascript/dashboard/helper/specs/calendarGrid.spec.js
app/javascript/dashboard/helper/specs/calendarTime.spec.js
app/javascript/dashboard/helper/specs/useCalendarCancelledVisibility.spec.js
app/javascript/dashboard/helper/useCalendarCancelledVisibility.js
app/javascript/dashboard/i18n/locale/en/settings.json
app/javascript/dashboard/i18n/locale/es/settings.json
app/javascript/dashboard/routes/dashboard/calendars/AgendaSidebar.vue
app/javascript/dashboard/routes/dashboard/calendars/CalendarView.vue
app/javascript/dashboard/routes/dashboard/calendars/EventBlock.vue
app/javascript/dashboard/routes/dashboard/calendars/EventModal.vue
app/javascript/dashboard/routes/dashboard/calendars/WeekGrid.vue
app/javascript/dashboard/routes/dashboard/calendars/specs/CalendarViewMenus.spec.js
app/javascript/dashboard/routes/dashboard/calendars/specs/EventBlock.spec.js
app/javascript/dashboard/routes/dashboard/calendars/specs/EventModal.spec.js
app/javascript/dashboard/routes/dashboard/calendars/specs/WeekGrid.spec.js
app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue
app/models/calendar_event.rb
app/services/calendar/appointment_attributes/updater.rb
config/locales/en.yml
config/locales/es.yml
docs/BUGS.md
docs/CITAS_FASE2_AB.md
enterprise/app/models/enterprise/calendar_event.rb
lib/integrations/google_calendar/event_service.rb
spec/controllers/api/v1/accounts/integrations/calendar_controller_spec.rb
spec/enterprise/services/captain/appointment_reminders_spec.rb
spec/lib/integrations/google_calendar/event_service_slots_spec.rb
spec/lib/integrations/google_calendar/event_service_spec.rb
spec/models/calendar_event_spec.rb
```
