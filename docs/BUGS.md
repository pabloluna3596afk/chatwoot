# Bugs abiertos y fixes aplicados — fork PaluHub (Chatwoot)

### B-NEW-236 — Nombre, foco y altura de las ventanas emergentes (UI-13)

- **Problema:** los diálogos no asociaban sus títulos y descripciones; los paneles laterales y las ventanas móviles no impedían llegar al fondo con el teclado. Los campos se montaban después de elegir el foco inicial.
- **Cambio:** Dialog, SidePanel y Popover comparten la modalidad nativa. Se asocian nombres y descripciones, se bloquea el cierre durante peticiones pendientes y los selectores permanecen dentro del diálogo. La altura usa dvh y respeta el área segura; las acciones comunes alcanzan 44 px en móvil.
- **Verificación:** specs de bases, selectores y consumidores en UTC y America/Guayaquil; piloto Captain con Editor y menú @ reales, foco inicial/retorno, Tab y Esc superior. Evidencia y límites en `tmp/PR-UI-13b.md`.
- **Archivos:** `app/javascript/dashboard/helper/overlayFocus.js`, bases Dialog/SidePanel/Popover, ComboBox, consumidores con encabezado propio y pruebas. Sin backend ni migraciones.

### B-NEW-231 — Menú de herramientas de Captain sobre el cursor y el pie (UI-10m)

- Archivos: `components-next/captain/assistant/ToolsDropdown.vue` y `components/widgets/conversation/TagTools.vue` (dashboard).
- Causa: el anclaje fijo `bottom-20` no seguía la línea escrita; el menú podía cubrirla y solaparse con Cancelar/Crear.
- Arreglo: medir el rango del cursor, elegir el lado con más espacio antes del pie y limitar la altura con scroll propio.
  El menú conserva MenuPopover, su contrato de slots y el portal dentro del diálogo nativo; sigue selección, scroll y resize.
- Verificación: `ToolsDropdown.spec.js` cubre posición, altura, pie, scroll, teclado y selección; comprobar a 390/1280
  escribiendo @ al final y a mitad de texto largo. Evidencia antes/después y mediciones: `tmp/PR-UI-10m.md`.
- El defecto ya existía en develop a mitad del texto; la rama también cubría el pie. Sin backend ni migraciones.

### B-NEW-210 — Reactividad de VueUse distinta entre Vitest local y CI (UI-09g)

- Archivos: `vitest.config.ts` y `InternalTasks/specs/TaskDetailHeader.spec.js`.
- Causa: VueUse externalizado usa otro runtime de Vue que los componentes con el alias
  `vue/dist/vue.esm-bundler.js`. El clic sí cambia `reassignOpen` a true, pero no dispara render;
  esperar con `vi.waitFor` no lo resuelve. Un render forzado de diagnóstico muestra el panel,
  y el cierre posterior también queda sin renderizar. No es un cierre por clic exterior.
- Arreglo: procesar `@vueuse/core`, `@vueuse/shared` y `@vueuse/components` en Vitest para
  compartir el runtime aliased, igual que ya hacía la configuración local. Comprobar apertura
  inmediatamente después del tick de `trigger`, sin espera por timeout ni render forzado.
- Verificación: reproducción roja sin inlining; cinco repeticiones verdes con threads, sin caché
  ni coverage y CI=true; los 7 casos de InternalTasks y routes/dashboard/tasks pasan en UTC y
  America/Guayaquil, con configuración local y con la base más la excepción de filesystem del
  worktree. ESLint pasa. Evidencia y límites en `tmp/PR-UI-09g.md`.
- Sin cambios de UI, backend, contratos, ACL ni migraciones; UI-09f conserva sus portales reales.

### B-NEW-205 — Catálogos existentes sin registrar en el dashboard (UI-01)

- Archivos: `app/javascript/dashboard/i18n/locale/{en,es}/index.js`.
- Causa: español no exportaba `contentTemplates`, `snooze` ni `yearInReview`; inglés no exportaba `calls`.
  La compilación de JSON individuales no detectaba que faltaban en el catálogo efectivo.
- Arreglo: registrar los cuatro catálogos existentes, sin modificar textos, claves ni registrar `webhooks`.
- Verificación: `i18n/messagesCompile.spec.js` comprueba hojas efectivas sin fallback, formulario de plantillas
  y sugerencias localizadas; `routes/dashboard/commands/specs/commandbar.spec.js` integra el catálogo real
  con las sugerencias de posposición en inglés y español. Ejecutar en UTC y America/Guayaquil.
- Sin cambios de backend ni migraciones. Capturas y revisión visual del dueño pendientes; detalle en `tmp/PR-UI-01.md` del worktree.

### B-NEW-194 — Cupo y ventana de automatizaciones solo tras elegibilidad y envío (2026-10-23)

- Archivo: `app/services/automations/contact_based_rule_runner.rb`.
- Causa: se reclamaba la ventana antes de resolver conversación y condiciones; el cupo usaba una comprobación
  separada del incremento y contaba incluso acciones que no enviaban mensajes.
- Arreglo: resolver y evaluar antes de reservar con `ProactiveSendCap#reserve!`; reclamar la ventana con NX,
  devolver la reserva si ya tiene dueño y liberar cupo/ventana propios cuando no aparece un mensaje público saliente.
  Las excepciones de la acción se registran por regla/contacto y el lote continúa. La pausa por cupo conserva su comportamiento.
- Asincronía: mensajes y adjuntos con demora, macros, flujos y transcripciones de correo conservan cupo/ventana
  de forma conservadora; no se puede verificar el mensaje futuro al terminar la acción.
- Verificación: `spec/services/automations/contact_based_rule_runner_spec.rb` cubre dos corridas, condiciones que cambian
  (once/yearly), etiquetas, notas privadas, envío múltiple, fallos, cupo agotado, demoras y conteo de candidatos.
  RSpec y RuboCop quedan pendientes del PM en Docker según `.codex/BRIEF-LIMITES.md`. Sin migraciones.

### B-NEW-193 — Simulación de automatizaciones sin efectos laterales (2026-10-23)

- Archivos: `app/services/automation_rules/{conditions_filter_service,condition_validation_service,simulation_service}.rb`
  y `app/controllers/api/v1/accounts/automation_rules_controller.rb`.
- Causa: la simulación llamaba al evaluador de runtime, que contabilizaba condiciones inválidas como errores de autorización;
  al segundo error podía desactivar la regla y encolar un correo.
- Arreglo: evaluación compartida de solo lectura en `evaluate`; `perform` conserva la reacción del runtime.
  La respuesta agrega `diagnostics` con regla, índice de condición (desde cero), atributo, operador y motivo.
  Los permisos, coincidencias válidas y descripciones de acciones se conservan.
- Verificación: specs de simulación (dos intentos sin cambios de datos, contador, estado de reautorización ni colas),
  diagnósticos, coincidencias válidas y último mensaje; specs de endpoint para administrador, agente y aislamiento de cuenta;
  regresión de runtime para contador, desactivación y correo. RSpec y RuboCop pendientes del PM en Docker según el brief.
- Sin migraciones. Antes de promover: ejecutar los specs y RuboCop indicados en `tmp/PR-SIMULACION.md` del worktree.

### B-NEW-192 — Lote UI del dueño: asignación Captain, citas y conversación (2026-10-22)

- Archivos: `app/services/conversations/assignment_service.rb`, concerns de actividades/asignación, `components-next/{date-field,time-field,dialog,dropdown-menu,sidebar}`, `calendars/EventModal.vue`, `AppointmentOriginLogo.vue`, `conversation/labels/LabelBox.vue`, etiquetas de tarjetas, `ContactInfo.vue`, `ViewAllConversations.vue` y locales es/en.
- Arreglo: una nota por asignación de Captain con marca `assignment_driven_status` y limpieza en `ensure`; conservar `pending` interno, el estado visible Abierta y el comportamiento AgentBot. Fecha/hora propios; invitación con área ampliable y vista previa plegada; logo de instalación para origen CRM. Modal real de etiquetas fuera del dropdown, aplicar la etiqueta creada y navegar por su nombre; botones de contacto compactos y un solo refrescar en Plantillas y Flows.
- Interacción: los menús de fecha/hora permanecen en el dialog nativo sin disparar su cierre exterior; evitar doble toggle por propagación del input de hora.
- Verificar: Vitest del lote en UTC y America/Guayaquil, ESLint de archivos tocados, capturas `lote-*` de `.codex/qa` a 390 px en ambos temas. RSpec nuevo en `spec/enterprise/services/conversations/assignment_service_spec.rb`: persona→Captain, Captain→persona, Captain A→B, persona→persona y limpieza del flag; revisión estática local según brief, ejecución Rails pendiente. Sin migraciones.

### B-NEW-230 — Variables desalineadas al enviar una plantilla de WhatsApp (2026-10-24)

- Archivos: `components-next/whatsapp/WhatsAppTemplateParser.vue`,
  `components-next/whatsapp/send-center/SendCenter.vue` y `components-next/content-templates/ContentTemplateParser.vue`.
- Causa: `1ebdc02bc20` agregó zona horaria/error como hijos directos del parser;
  la cuadrícula del centro de envío los trató como celdas adicionales, separando las variables verticalmente.
- Arreglo: bloques explícitos de formulario y vista previa; zona horaria/error dentro del formulario,
  columnas lista → variables → vista previa en escritorio y una columna en móvil, sin posicionamiento absoluto de variables.
- Verificación: 404 pruebas en UTC y 404 en America/Guayaquil, incluidos ReplyBox, Captain y ambos parsers;
  ESLint sin errores y capturas pareadas a 1280×900 y 390×844 con componentes reales.
  El parser conserva literalmente el valor recibido de la API; no se modifican nombres de contactos ni traducciones.

### B-NEW-195 — Contrato de automatizaciones validado al guardar (2026-10-23)

- Archivos: `app/models/automation_rule.rb`, `app/services/automation_rules/{condition_validation_service,action_validation_service}.rb`,
  `app/controllers/api/v1/accounts/automation_rules_controller.rb` y `app/controllers/concerns/attachment_concern.rb`.
- Causa: el guardado aceptaba eventos, operadores, programaciones y parámetros de acciones que el motor no podía ejecutar.
- Arreglo: el modelo reutiliza el validador del evaluador para las condiciones y valida evento, kind y acciones antes de persistir.
  Errores en inglés con índices desde cero, bajo las claves existentes. Las reglas antiguas pueden renombrarse y activarse/desactivarse
  sin revalidar su definición; al editar condiciones, acciones o evento se valida el contrato completo.
- Compatibilidad: Captain, macros, SLA Enterprise y las cinco recetas de contacto tienen cobertura; se corrigen fixtures inválidas.
  La simulación y la validación no cambian `active`; el evaluador conserva la reacción de autorización del runtime.
  Adjuntos sin parámetros devuelven el 422 existente en vez de invocar `first` sobre nil.
- Verificación: análisis sintáctico estático de Ruby y `git diff --check`; specs de modelo, servicio, API y Enterprise agregados.
  RSpec y RuboCop pendientes del PM en Docker, según `.codex/BRIEF-CONTRATO.md`.
- Sin migraciones ni frontend. Informe y comandos de verificación en `tmp/PR-CONTRATO.md` de `wt-auto-contrato`.

### B-NEW-191 - Audience condition actions overflow on mobile

- File: `app/javascript/dashboard/components-next/captain/pageComponents/assistant/settings/audience/AudienceGroup.vue`.
- Fix: allow Add condition and Add condition group to wrap onto separate lines. The shared base/custom audience editor otherwise overflows at 390 px in Spanish.
- Verify: open Captain → Assistant → Settings → Audience with a specific base rule, then open an inbox's custom advanced conditions at 390 px. Actions remain visible without horizontal scrolling. Reviewed the four `audiencia-*.png` captures in the external montage directory; browser smoke also checks the expanded custom editor.
- Scope: presentation only; no backend changes or migrations.

### B-NEW-190 - Compact sidebar sections menu

- Files: `SidebarVisibilityMenu.vue`, `MenuPopover.vue`, `useUISettings.js`, conversation i18n es/en and menu specs.
- Fix: 320 px menu with a compact two-line header, icon-only Reset, shared checkboxes, 32 px section rows and 28 px indented category rows. Labels wrap onto two lines; the list uses up to min(60vh, 32rem) with a thin scrollbar. Category groups start expanded, can fold independently of visibility, and persist per user. Reset clears folding with the other preferences in a single update.
- Dependencies: optional MenuPopover maxHeight keeps its 320 px default for other callers; this menu opts into extra height while retaining viewport positioning. Explicit empty visibility now means zero visible sections, matching the checkbox state and empty notice.
- Verify: menu, MenuPopover and useUISettings specs in UTC and America/Guayaquil; ESLint of touched JS/Vue. Reviewed `.codex/qa/menu-secciones-390-{light,dark}.png` with the real menu, six sections and five categories: no clipped labels or horizontal overflow. Browser smoke: folding survives reload, Reset expands groups, actual section dragging saves order and leaves the menu open. No backend or migrations.

### B-NEW-189 - Compact contact tools and restored conversation accordions

- Files: `ContactToolsBar.vue`, `ContactPanel.vue`, `ConversationAction.vue` and their toolbar/count specs.
- Fix: supersedes the panel organization in B-NEW-188. Restore Conversation actions with its four fields, the original section order and SidebarVisibilityMenu; keep empty sections visible with their counters. Remove the Conversation heading and empty-section summary. Keep the approved chevrons, contact menu, message/call controls and tools registry.
- Tools: one compact 36 px pill per active tool, 16 px colored icon and a single truncated legend; one shared gray pill for idle tools. No exterior box, separator or 32 px icon buttons. Keep calendar opening/creation and appointment refresh behavior.
- Verify: 28 tests passed in UTC and America/Guayaquil (tools, toolbar, calendar panel actions, section counts/order/visibility, contact menu, chevrons). ESLint: zero errors, existing root-v-if warning. Six reviewed `barra2-preset-{1,2,4}-390-{light,dark}.png` captures; all pills 36 px, no horizontal overflow. No backend or migrations.

### B-NEW-188 — Herramientas del contacto sin duplicados y secciones por contenido

**Archivos:** `ContactToolsBar.vue`, `useContactTools.js`, `ContactPanel.vue`,
`ConversationAction.vue`, `CalendarEventsList.vue`, `useAppointmentEvents.js`
e i18n es/en de conversación.

**Problema y solución:** la barra en preparación repetía las herramientas activas
como iconos y leyendas separadas. Cada herramienta aparece una sola vez: activas
arriba con su leyenda; inactivas abajo en una fila gris; separador solo con ambos
grupos. Captain y Citas reutilizan los estados y datos existentes. Las acciones de
conversación quedan visibles sin acordeón; los contadores cero pasan a «Sin datos»
y se pueden abrir para agregar contenido. Se conserva el orden y la visibilidad.
Al abrir Citas se monta su contenido antes de guardar las preferencias; el contador
solo se publica al recibir los eventos, evitando un cero transitorio que desmontaba
la lista antes de mostrar las citas. Se cancela la petición si se desconecta el
calendario. Pago y Carrito existen solo en el arnés local. No se restauran las
alturas uniformes de 40 px de B-NEW-187 (revertidas en `3a20f4e2b6`).
Sin backend ni migraciones.

**Cómo probar:** probar Captain activo, escalado, inactivo y sin asistente; Citas
con próxima cita y sin citas; pulsar «Agendar» y comprobar que abre Nueva cita.
Ocultar Citas desde el menú y abrirla desde la barra; comprobar la apertura incluso
si tarda el guardado de preferencias. Revisar secciones desconocidas, con datos y
vacías; revelar una vacía y cambiar de conversación. Specs: `useContactTools`,
`ContactToolsBar`, `ContactPanelCounts`, `ContactPanelAppointments`,
`CalendarEventsList`, `useAppointmentEvents`, `AppointmentRefresh` y
`NextAppointmentCard`, en UTC y America/Guayaquil. Capturas: `barra-preset-*`
en el directorio externo de montaje; informe local `tmp/PR-BARRA.md`.

### B-NEW-187 — Panel de contacto: campos uniformes, contadores y acciones secundarias

**Archivos:** `ContactPanel.vue`, `contact/ContactInfo.vue`, `contact/ContactInfoRow.vue`,
`OutlinedSelectField.vue`, `AccordionItem.vue` e i18n de contacto en es/en.

**Problema y solución:** las filas de datos, los desplegables y las cabeceras compactas
tenían alturas distintas. Ahora miden 40 px y alinean los iconos. Combinar y eliminar
se encuentran en el menú Más; solo administradores ven eliminar y deben confirmar.
Se reutilizan los diálogos de `components-next`. Los botones de copiar y editar tienen
nombre accesible. Participantes, conversaciones anteriores, notas, tareas y adjuntos
muestran el número disponible en la caché, sin nuevas peticiones ni ceros inventados.
Se mantienen las correcciones previas de campos vacíos, responsables y lápiz táctil.
Sin backend ni migraciones.

**Cómo probar:** abrir una conversación con contacto completo y otra sin datos, en
es/en, claro/oscuro y 390 px. Revisar los contadores antes y después de cargar las
secciones y al cambiar de conversación. Abrir Más como administrador y agente;
eliminar solo debe despachar la acción después de confirmar. Verificar edición,
combinación y cierre del menú con Escape. Specs: `ContactInfo`, `ContactInfoRow`,
`ContactPanelCounts`, `AccordionItem`, `OutlinedSelectField` y regresión de citas.

### B-NEW-187 — Recordatorio de citas humanas por WhatsApp, con consentimiento y sin duplicados

**Archivos:** `Calendar::ActivationKit`, `CalendarEvent`, `Calendar::CustomerReminders::{Dispatcher,Schedule,Delivery}`,
`Calendar::AppointmentRemindersJob`, `SendReplyJob`, `CustomerNotice`, `TemplateButtonReply`, tarjeta del kit y API de ajustes.

**Cambio:** tercera plantilla `cita_recordatorio` es/en y un interruptor de cuenta apagado por defecto, editable solo por admin.
El cron existente reclama la cita con bloqueo de fila y encola la plantilla. La entrega marca `sent` solo cuando Meta acepta;
libera el cupo diario y reintenta hasta tres errores. No repite la nota de plantilla pendiente. Excluye Captain, Panel AI,
confirmadas, canceladas, citas pasadas y las creadas/movidas con menos de 24 h. Adelanta la hora nocturna a las 21:00 según
la zona de la cuenta; una cola retrasada tampoco envía de madrugada. Al mover la cita limpia los marcadores.
La reserva del tope conserva su fecha para no descontar otro día. Los errores del proveedor no registran el cuerpo sensible.

**Migración requerida:** `20261022120000_add_customer_reminder_to_calendar_events` (dos columnas nullable e índice parcial concurrente).

**Cómo probar:** aplicar las tres plantillas; activar el interruptor como admin; agendar una cita humana con más de 24 h,
ejecutar dos corridas y comprobar un solo recordatorio y sus botones. Probar plantilla pendiente, confirmación previa,
reagenda, errores de Meta y tope agotado. R1–R16 y concurrencia están escritos en
`spec/services/calendar/customer_reminders/`; ejecución RSpec/RuboCop en Docker pendiente del PM.
Vitest de Integraciones: 40 pruebas pasan en UTC y America/Guayaquil. Capturas `rec-*` en el directorio externo de montaje.
Ver `tmp/PR-RECORDATORIO.md` y `docs-crm/codex/resumen-recordatorio.md` (ambos fuera del commit).

### B-NEW-186 — Asignar a Captain desde automatizaciones y macros

**Archivos:** `ActionService`, extensión Enterprise, hook/job de Captain, payload de
Bandejas, editores de automatizaciones y macros, `ConnectInboxForm` y onboarding
del asistente. Los Flujos quedan fuera (van a salir del sistema).

**Problema y solución:** «Asignar al agente» solo aceptaba personas. Ahora acepta
`captain` y `captain:<id>` y reutiliza `Conversations::AssignmentService`: quita al
humano, asigna al asistente conectado y deja Pendiente. La orden explícita no
reevalúa audiencia ni horario. Sin función, conexión, coincidencia del asistente,
clave/cupo, o con bot externo activo, conserva estado/responsable y deja una nota
privada con el motivo. La repetición de
una asignación pendiente al mismo Captain no escribe. El hook y los trabajos ya
encolados esperan un mensaje del cliente posterior a la orden.

Los editores muestran Captain general y los asistentes por nombre, conservan
referencias eliminadas y advierten sobre Bandejas incompatibles sin impedir el
guardado. Las Bandejas ocupadas siguen visibles, deshabilitadas y con el nombre
del asistente conectado. El payload precarga esa asociación y su caché se
invalida al conectar, desconectar o renombrar. Sin migraciones.

**Cómo probar:** elegir Captain en una regla o macro;
probar cada guarda, conversación resuelta y humano asignado; comprobar que solo
responde al siguiente mensaje del cliente. Reabrir una regla con asistente
eliminado y conectar una Bandeja ocupada. Evidencia local y límites de la
validación en `tmp/PR-CAPTAIN-ASIGNAR.md` (ignorado).

### B-NEW-185 — Mock único de cuenta en la próxima cita tras integrar develop

**Archivo:** `app/javascript/dashboard/components/widgets/conversation/specs/NextAppointmentCard.spec.js`.

**Causa y fix:** la integración de develop dejó dos imports de `ref` y dos mocks
de `useAccount` en el mismo spec. ESLint abortaba con `Identifier 'ref' has already
been declared`. Se conserva un solo import y un mock con `accountId` y
`calendar_timezone: 'America/Guayaquil'`, manteniendo todas las aserciones.
No cambia código de producción.

**Cómo probar:** ejecutar ESLint sobre el archivo y Vitest sobre las carpetas de
specs de conversación, calendario, helpers, composables y ajustes del asistente
en UTC y America/Guayaquil. Ver el informe externo `docs-crm/codex/validar-c.md`
para comandos y resultados de la validación del bloque C.

### B-NEW-091 - Próxima cita vigente y errores de carga visibles (CIT-16 / CIT-26)

**Archivos:** `CalendarEvent`, `useAppointmentEvents`, `useAppointmentClock`,
`actionCable.js`, `NextAppointmentCard.vue`, `CalendarEventsList.vue`, cliente
Calendar, mensajes en/es de conversación y specs de modelo/job/UI.

**Fix:** después del commit de una cita se invalida su contacto en el canal
existente de la cuenta, incluyendo el contacto anterior al reasociar. El mensaje
solo lleva IDs; lista y tarjeta vuelven a consultar sus endpoints autorizados.
Funciona para cambios humanos/Captain y sin atributos opcionales de citas.
Cambiar solo etag no emite ni provoca bucles de lectura. Se conserva el refresh
local al guardar desde ContactPanel y se recarga después de recuperar WebSocket.
Las solicitudes se cancelan al cambiar cuenta/contacto/conversación o desmontar.
Un timeout en la siguiente frontera temporal recalcula sin polling; al volver
a una pestaña suspendida se actualiza el reloj. Se mantiene el contrato existente:
una cita en curso sigue siendo próxima hasta su fin. Las canceladas se excluyen.
Lista y tarjeta distinguen error de vacío real y ofrecen reintento localizado.

**Cómo probar:** mantener abiertos dos contactos, crear/mover/cancelar una cita
del primero desde calendario u otro cliente y comprobar su actualización sin
remontar ni cambiar el segundo. Dejar vencer una cita y comprobar la siguiente.
Cambiar contacto con una petición pendiente: la respuesta anterior no aparece.
Simular 503, reintentar y comparar con un contacto realmente sin citas.

**Evidencia local (2026-10-21):** seis regresiones frontend fallan sobre la base;
también falla la integración ContactPanel con la tarjeta original. En backend,
cuatro regresiones fallan sin el callback. Verde: 115 tests por zona UTC y
America/Guayaquil; 20 ejemplos RSpec sin fallos, PostgreSQL/Redis exclusivos.
ESLint sin errores (cinco warnings heredados), Prettier y diff check aprobados.
RuboCop exacto CI en chathub-rubocop-ci:cit5-ruby344 pasa sobre 42 Ruby de la
cadena; inspected_file_count=42. Los tres Ruby de esta tarea pasan completos;
el reporte global conserva 90 infracciones heredadas fuera de líneas cambiadas.
Veinte capturas cit10- revisadas, 1280/390, claro/oscuro, dos contactos,
actualización/vacío/error/reintento con componentes reales y APIs simuladas.
Sin migraciones. Pendientes CI remoto y smoke Google aislado; las capturas
no acreditan operaciones ni entrega de proveedor. Integrar PR1 → … → PR10;
esta rama parte localmente del PR9. Sin push ni cambios a AGENTS.md.

### B-NEW-090 - Conexión propietaria y respuestas vigentes de Citas (CIT-15 / CIT-17)

**Archivos:** `CalendarView.vue`, `CalendarEventsList.vue`, `EventModal.vue`,
`AssistantAppointmentsForm.vue`, clientes Calendar/Search, `useAbortableRequest`
y specs de esas superficies. Fuentes nuevas solo en `en/settings.json`.

**Fix:** desde conversación se puede elegir otra conexión al crear. El modal
carga los calendarios de esa conexión y mantiene cuenta/calendario bloqueados
al editar un evento existente. Muestra carga, fallo y reintento de calendarios;
en móvil los selectores ocupan filas completas. Las lecturas usan cancelación
compartida con señal hasta axios, incluida la búsqueda de contactos/conversaciones,
invitación y adquisición del lock del modal. Se invalidan al cambiar contexto,
cerrar o desmontar. El composable descarta incluso una respuesta resuelta por
un transporte que ignore el aborto. Cambiar conexión con el mismo calendar_id
recarga eventos; guardar en otra conexión no inserta el evento en la vista actual.

**Cómo probar:** con dos conexiones Google, crear desde una conversación usando
la segunda; reabrir el evento y comprobar sus opciones y propietario fijo.
Alternar conexión con calendar_id compartido, semana, calendario, conversación
y asistente con solicitudes pendientes: solo se aplica la respuesta vigente.
Cerrar el modal durante búsquedas o desmontar las vistas no muestra cancelación
como error. Simular fallo al cargar calendarios y reintentar.

**Evidencia local (2026-10-21):** seis regresiones conductuales nuevas fallan
antes del cambio sobre las cuatro superficies. Verde final: 112 tests por zona
(UTC / America/Guayaquil), incluidos contratos de señal axios e i18n en/es.
ESLint sin errores (13 warnings heredados), Prettier y diff check aprobados.
RuboCop exacto CI aprobado, imagen chathub-rubocop-ci:cit5-ruby344, 40 Ruby de
la cadena inspeccionados; reporte completo conserva 90 infracciones heredadas
fuera de líneas cambiadas. Este PR no toca Ruby; no ejecuta RSpec ni migraciones.
16 capturas cit9- de componentes reales con API simulada en 1280/390 y claro/oscuro,
revisadas visualmente, más vídeo de cambio rápido. Pendientes CI remoto, smoke
con Google real y Crowdin de tres textos nuevos (fallback inglés comprobado en
español). No cubre CIT-16/26 ni entrega de recordatorios. Rama local
feat/citas-conexion-respuestas basada en f25807dc78 de PR8; integrar PR1 → … → PR9.
Sin fetch, stash, push ni deploy. Informe: tmp/PR-CITAS-10.md (ignorado).

### B-NEW-089 - Preparación de recordatorios por bandeja (CIT-07 / CIT-28)

**Archivos:** `AppointmentReminderReadiness.vue`, `AssistantAppointmentsForm.vue`,
`Captain::AppointmentReminders::Readiness`, sender, serializer del asistente,
AssistantsController y AppointmentsValidator; specs del formulario, panel,
readiness y contratos request; traducciones en/es.

**Fix:** estado de configuración guardada por bandeja, con Captain/citas activos,
canal, permiso de pago, plantilla aprobada en esa bandeja y bindings completos.
Comparte comprobaciones/códigos con el sender y reutiliza TemplateMessage y
Variables, sin otro resolver. Explica los límites de ventana y valores concretos
al enviar; enlaza Mensajes de pago. Mantiene 24 h / 3 h y pago optativo. Oculta
el selector sin consumidor de cancelación y conserva la referencia histórica al
guardar otros campos, aunque la plantilla haya cambiado en Meta.

**Cómo probar:** conectar dos bandejas con la misma plantilla, aprobada solo en
una; guardar y comprobar estados diferentes. Desactivar pago: aparece el motivo
de omisión fuera de ventana. Cambiar variables de la plantilla: muestra bindings
pendientes. Guardar otros ajustes conserva template_cancelled. Un valor de contacto
ausente al enviar deja nota privada y el diagnóstico existente del motor.

**Evidencia local (2026-10-21):** 103 ejemplos Rails y 39 tests frontend por zona
(UTC / America/Guayaquil) sin fallos; RuboCop exacto CI aprobado sobre 40 Ruby
inspeccionados, ESLint sin errores y Prettier aprobado. 32 capturas cit8- en
1280/390 y claro/oscuro revisadas, componentes reales con datos simulados.
Rojo/verde conductual demostrado en formulario y dos contratos request; las
regresiones existentes de sender/TemplateMessage no tienen rojo previo nuevo.
Pendientes CI remoto y entrega real autorizada dentro/fuera de ventana. Sin
migraciones ni push. Rama local feat/citas-recordatorios-estado sobre PR7;
integrar PR1 → … → PR8. Informe: tmp/PR-CITAS-9.md (ignorado).

### B-NEW-088 - Atributos de cita disponibles en el alta de Captain (CIT-06)

**Archivos:** `AssistantAppointmentsForm.vue` y su spec; specs del controlador
`calendar_appointment_attributes`, `updater_onboarding_contract` y `event_service`.

**Fix:** el alta muestra el panel existente `CalendarAppointmentAttributes`, con
seleccion optativa y resultados por clave. Usa el controlador de Integraciones y
Provisioner existentes; la preferencia pertenece a la cuenta. El panel queda
fuera del toggle de Captain: activarlo nuevamente no escribe ni restablece claves,
incluida una seleccion vacia guardada. Los dos botones guardan sus respectivas
secciones. Los conflictos conservan definicion y valor; no hay cambios al motor
de variables, al contrato API ni a la configuracion del asistente.

**Como probar:** desde Captain > Ajustes > Citas, habilitar los cuatro atributos
en una cuenta nueva y comprobar resultados; recargar, desmarcarlos todos y guardar,
volver a activar Captain: siguen desmarcados. Con `ultima_cita` de tipo texto,
reintentar muestra conflicto y mantiene su valor. Reservar y procesar jobs actualiza
los cuatro derivados; el catalogo y el editor de contactos mantienen lectura sola.

**Evidencia local (2026-10-21):** 136 ejemplos RSpec sin fallos, 34 tests Vitest
por zona (UTC y America/Guayaquil), ESLint/Prettier aprobados. RuboCop exacto de CI
sin infracciones en lineas cambiadas, 35 Ruby inspeccionados; los tres specs propios
sin infracciones completas. Doce capturas `cit7-` claro/oscuro, 1280/390 px, con
componentes reales y datos simulados, revisadas visualmente. Rojo/verde del cambio
demostrado en tres casos del formulario; el backend reutilizado ya pasaba en la
base, por lo que no se reclama rojo/verde backend. Sin migraciones. Pendientes CI
remoto y smoke con Google real. Detalle: `tmp/PR-CITAS-8.md` (ignorado).


### B-NEW-184 — Fixtures de cuenta en specs de tarjetas de citas

**Archivos:** `CalendarEventsList.spec.js`, `NextAppointmentCard.spec.js`.

**Causa:** las tarjetas usan `useCalendarTime`, que lee la cuenta mediante
`useAccount`. Los specs montaban las tarjetas sin cuenta, store ni router;
esto provocaba cinco rechazos sin manejar y cuatro aserciones fallidas.

**Fix:** proporcionar una cuenta con `calendar_timezone` mediante el mock de
`useAccount`, conservando las aserciones existentes y comprobando además que
ambas tarjetas muestran `America/Guayaquil`.

**Cómo probar:** ejecutar los seis ejemplos de ambos archivos con Vitest en
`TZ=UTC` y `TZ=America/Guayaquil`; deben pasar sin rechazos sin manejar.

### B-NEW-087 — Una zona de cuenta en todo el recorrido de Citas (CIT-02)

**Archivos:** `lib/integrations/google_calendar/timezone.rb`, servicio de eventos,
controlador de Calendar, serializers de cuenta/perfil, herramientas y remitente
Captain; `calendarTime.js`, `calendarGrid.js`, `useCalendarTime.js`, vistas de
calendario/modal y tarjetas de conversación, más sus specs.

**Fix:** `reporting_timezone` determina una sola zona efectiva, normalizada a
IANA para Google y el dashboard. Sin configuración se conserva America/Guayaquil;
el fallback de informes sigue independiente. `calendar_timezone` se expone al
iniciar sesión y al refrescar la cuenta. Semana, agenda, límites de consulta,
edición, historial, errores, invitación y Captain usan esa misma zona. La zona
se muestra en calendario, modal y conversación.

Una hora local inexistente por DST se rechaza. Una hora local repetida selecciona
la primera ocurrencia; un ISO con offset explícito identifica cualquiera de las
dos. Editar sin cambiar los campos civiles conserva el instante original, incluida
la segunda ocurrencia. Los all-day mantienen su fecha civil. La grilla usa minutos
del reloj local; las dos ocurrencias de una hora repetida ocupan carriles separados.
Una cita que atraviesa un cambio DST se divide en tramos con el mismo ID: conserva
su duraci?n en el retroceso y deja vac?a la hora inexistente al adelantar.

**Cómo probar:** configurar Guayaquil y New York, crear a las 10:00 en julio,
recargar y comparar semana/modal/conversación/invitación. Verificar semana del
10/03/2030, hora inexistente 02:30 y hora repetida 01:30 del 03/11/2030, además
del cambio 31/12 → 01/01 y fechas all-day. Validar Captain y variables del
recordatorio contra el mismo instante persistido.

**Validación local:** regresión RSpec de 366 ejemplos sin fallos; 12 ejemplos
adicionales sobre el código final sin fallos. Vitest: 67 tests en UTC y 67 en
America/Guayaquil, con modal en ingles y espanol y cuentas de ambas zonas. Rojo reproducido
en la base: diez fallos frontend y cuatro backend. ESLint sin errores; filtro
exacto de RuboCop CI aprobado, 33 archivos Ruby inspeccionados. El fixture de
reintentos ahora simula `get_event`; su fallo se reprodujo en la base intacta.

**Pendiente antes de integrar:** workflow remoto, Google/canal reales y capturas
claro/oscuro/390 px de ambas zonas. Computer-use no tuvo superficies habilitadas;
no se generaron capturas. La nueva ayuda DST tiene fuente inglesa y usa fallback
en español hasta Crowdin. Sin migraciones ni cambios a Panel AI. Rama local
`feat/citas-zona-horaria`, dependiente de PR5: integrar PR1 → … → PR6. Sin push.
Informe completo ignorado: `tmp/PR-CITAS-7.md`.

### B-NEW-086 — Reconciliar Google antes de enviar recordatorios (CIT-08)

**Archivos:** `lib/integrations/google_calendar/event_service.rb`,
`app/jobs/calendar/reconcile_events_job.rb`, `config/schedule.yml`,
`enterprise/app/services/captain/appointment_reminders/{sender,dispatcher}.rb`,
`enterprise/app/models/enterprise/calendar_event.rb`, reconciliador manual y specs.

**Fix:** cada intento de envío consulta una sola versión del evento en Google.
Sincroniza título, intervalo e invitación; 404/410 o estado cancelled cancelan
la fila local, liberan su clave y cancelan recordatorios pendientes. Un rechazo
de invitación no cancela la cita. Timeout/5xx conservan el pendiente sin enviar.
El remitente bloquea primero la cita y luego el recordatorio, y vuelve a leer
su estado y vencimiento después de reconciliar. Cambiar la hora modifica las
filas existentes: no crea otro recordatorio del mismo tipo.

La sincronización Enterprise de recordatorios ahora ocurre dentro de la misma
transacción que el cambio de cita; un rollback revierte ambos. El job periódico
recorre citas vinculadas a contacto o conversación, humanas y Captain, cada
cinco minutos: páginas de 100 con cursor por ID, futuras y terminadas durante
el último día. Los atributos del contacto se recalculan mediante el callback
existente. No activa recordatorios Captain para citas humanas ni modifica Panel AI.
El rake manual usa la misma reconciliación al aplicar; conserva su modo de consulta.

**Cómo probar:** mover/cambiar título en Google sin abrir el calendario; ejecutar
la tarea periódica y revisar fila, atributos y recordatorios. Ejecutar el despacho
en la hora anterior: cero mensajes; en la nueva: uno, incluso al repetir. Borrar
o cancelar en Google: cero envíos y fila fuera de kept. Simular timeout/5xx:
ningún envío ni cancelación; recuperar Google y repetir: un solo mensaje.

**Verificación local (2026-10-21):** diez ejemplos finales fallan contra la base
original `67ad570ef2`; 316 ejemplos de regresión pasan con el fix. DB y Redis
exclusivos, Google/canal simulados. Se corrigieron dos helpers de fixtures que
ignoraban la conexión solicitada por crear a través de una asociación: los once
fallos correspondientes también se reprodujeron en la base intacta, y pasan
con los fixtures corregidos. Lint exacto CI aprobado en
`chathub-rubocop-ci:cit5-ruby344`, 29 Ruby inspeccionados; 85 infracciones del
reporte completo quedan fuera de líneas cambiadas. Sin migraciones ni UI.

**Pendiente de integración/deploy:** PR5 `feat/citas-reconciliar` depende
localmente de PR4 `feat/citas-oauth-state`; integrar PR1 → PR2 → PR3 → PR4 → PR5.
Sin push ni deploy. Reiniciar Rails y Sidekiq al desplegar para cargar código
y cron. Faltan CI remoto, Google/canal reales, recepción efectiva y prueba con
dos procesos simultáneos. El barrido automático no recupera movimientos de
citas cuyo final local ya quedó más de un día atrás; un backfill histórico
requeriría otro recorrido explícito. Evidencia: `tmp/PR-CITAS-6.md` (ignorado).

### B-NEW-201 — Condiciones de automatización por canal, horario y estado de Captain (2026-10-23)

- **Cambio:** `channel_type`, `within_business_hours` y `captain_state` comparten el catálogo de
  `lib/filters/filter_keys.yml` entre modelo, validador y evaluador. Valores y operadores inv?lidos devuelven 422
  con el nombre de la condición; `within_business_hours` acepta únicamente `equal_to` y booleanos JSON.
- **Semántica:** resolver de canales común a automatizaciones y Captain (`Conversations::ChannelType`), incluidos
  Twilio WhatsApp e Instagram vía Facebook; horario delegado a `Inbox#out_of_office?` con su zona horaria;
  Captain delegado a `Conversation#captain_state`, con ausencia representada por `none`.
- **Compatibilidad:** condiciones marcadas `automation_only`, excluidas de los filtros generales y segmentos.
  Sin frontend, migraciones ni cambios en listeners/runners; simulación usa el mismo evaluador.
- **Cómo probar:** reglas con cada condición y su inversa; horario activado/desactivado; estados `none`, `ai`,
  `escalated`; guardar valores inv?lidos; simular y ejecutar por evento/tiempo. Specs ampliados en
  `spec/services/automation_rules/`, `spec/services/automations/time_based_rule_runner_spec.rb`,
  `spec/listeners/automation_rule_listener_spec.rb`, `spec/controllers/api/v1/accounts/automation_rules_controller_spec.rb`,
  `spec/services/conversations/filter_service_spec.rb` y `spec/enterprise/services/captain/engagement_activity_spec.rb`.
- **Verificación:** revisión estática; RSpec y RuboCop en Docker pendientes del PM según el brief. Sin push.

### B-NEW-085 — State OAuth de Calendar consumible una sola vez (CIT-29)

**Archivos:** `app/helpers/google_calendar/integration_helper.rb`,
`app/controllers/google_calendar/callbacks_controller.rb`, sus dos specs y
mensajes de error en `config/locales/en.yml` y `config/locales/es.yml`.

**Fix:** cada autorización recibe un nonce aleatorio, cuenta, usuario, huella
de sesión y vencimiento firmado de 10 minutos. Redis conserva la huella del
state con el mismo TTL. El callback lo consume con GET y DEL en MULTI/EXEC
antes de intercambiar el código, incluso ante cancelación o fallo posterior.
Se utiliza la transacción porque redis-namespace 1.x no aplica su namespace a
GETDEL. Un replay no llega a Google ni cambia conexiones o tokens.

El callback comprueba la cookie iniciadora, el usuario autenticado si lo hay,
la pertenencia y el rol administrador actuales y que la cuenta siga activa.
La cookie enlaza el callback del navegador con el inicio autenticado por
cabeceras del dashboard; Google no devuelve esas cabeceras. `connected_by`
conserva al usuario iniciador. Reconectar por email mantiene el refresh token
anterior cuando Google lo omite. Los errores devuelven 422 con mensajes en
inglés y español neutro, sin detalles del proveedor.

**Cómo probar:** conectar y reconectar; repetir el callback después de éxito,
cancelación, código ausente o fallo del proveedor; esperar el vencimiento;
usar otra sesión/usuario/cuenta o revocar permisos antes del retorno. Ningún
rechazo debe intercambiar el código. Con Redis real, ocho consumidores del
mismo state deben producir exactamente una aceptación.

**Verificación local (2026-10-21):** mismos specs Rails contra fuentes de
`2a13eb9f32`: 24 fallos; con el fix: 24 ejemplos aprobados. PostgreSQL y Redis
exclusivos, sin bases compartidas. Comando exacto de lint CI aprobado en
`chathub-rubocop-ci:cit5-ruby344` (Ruby 3.4.4, dependencias del lockfile): cero
infracciones en líneas cambiadas de los 20 Ruby de la pila. El reporte completo
inspecciona 20 archivos y conserva 68 infracciones fuera de las líneas del PR.
Tras corregir indentación en specs se releyeron bloques, Ruby 3 kwargs y
consumo atómico. Sin migraciones, cambios visuales, capturas ni OAuth real.

**Pendiente de integración:** PR1 → PR2 → PR3 → PR4; rama local
`feat/citas-oauth-state` basada en `feat/citas-exclusion-meet`. Falta ejecución
remota del CI y smoke con Google en cuenta de prueba; sin push ni despliegue.
Los pendientes funcionales heredados de PR1–PR3 no se dan por cerrados aquí.

### B-NEW-183 — Fixtures de propiedad e idempotencia del CI de citas (PR #183)

**Archivos:** `spec/lib/integrations/google_calendar/event_service_spec.rb`,
`spec/enterprise/lib/captain/tools/appointment_tools_spec.rb`,
`spec/controllers/api/v1/accounts/integrations/calendar_controller_spec.rb`.

**Causa y fix:** los helpers creaban mediante `connection.calendar_events`,
que imponía esa conexión sobre la conexión ajena solicitada por el ejemplo y
retenía en su colección la fila destruida. Ahora crean con `CalendarEvent`,
con conexión predeterminada explícita y atributos del ejemplo aplicados después.
El reintento idempotente necesita leer el evento Google para recuperar Meet;
el double del request spec no admitía `get_event` y causaba HTTP 500, no un
rechazo de intervalo. Se simula esa lectura y se exige HTTP 200 en ambos POST,
el mismo evento, un solo POST a Google y una sola lectura de recuperación.
Se conservan todas las aserciones de aislamiento; no cambia código de producción.

**Cómo probar:** ejecutar los tres archivos anteriores: la base intacta reproduce
303 ejemplos con los mismos 12 fallos del CI. Luego ejecutar la regresión de
calendario y Captain con los fixtures corregidos, incluyendo las pruebas de
recuperación Meet y exclusión con Redis real. Sin migraciones.

### B-NEW-084 — Lease de reservas y recuperación de Meet (CIT-12 / CIT-31)

**Archivos:** `lib/integrations/google_calendar/booking_lock.rb`,
`lib/integrations/google_calendar/event_service.rb`, specs de lock, servicio,
invitación y herramientas Captain, y `spec/support/real_redis.rb`.

**Fix:** el lease renueva cada 5 s mediante WATCH/MULTI condicionado al token;
una pérdida o error de renovación invalida permanentemente la operación. Antes
de cada nueva fase de escritura se comprueba la propiedad. El heartbeat se
detiene y la liberación en ensure conserva compare-and-delete: no elimina el
token de otro worker. La prueba real espera 21 s, sin travel_to.

El resultado del POST/PATCH principal se persiste antes de completar la
descripción Meet: conserva identidad, intervalo, clave, asociaciones, invitación,
estado y política de seguimiento. Un fallo del PATCH opcional se registra y no
impide el seguimiento normal. Reintentar con la misma clave lee el evento Google
existente y completa la descripción sin otro POST ni duplicar notificaciones.
Si se pierde el lease durante una petición ya enviada, se conserva su resultado
local como reconciliación, pero se detienen las fases siguientes. No se promete
deshacer un POST remoto ni exclusión por fencing que Google no ofrece.

**Cómo probar:** con Redis real y namespace aislado, retrasar Google más de 20 s
y competir por el mismo calendario; reemplazar el token durante la lectura y
durante el POST. No debe haber nuevas escrituras tras detectar la pérdida ni
borrado del token ajeno; un POST ya finalizado debe quedar identificable.
Simular timeout al completar Meet al crear/editar: la reserva y el PATCH
principal permanecen; repetir la reserva idempotente repara la descripción sin
otro evento. Captain confirma y programa los recordatorios una sola vez.

**Verificación local (2026-10-21):** los cinco ejemplos del lock, con el mismo
spec y soporte del repo en runner aislado sin Rails/DB, fallan contra el lock
anterior y pasan con el nuevo; Redis 7 real y gems Redis del lockfile. Smoke de
compatibilidad MockRedis aprobado. Sintaxis Ruby aprobada en 16 archivos de la
pila; RuboCop directo en imagen `chathub-rubocop-ci` inspecciona 16 archivos,
66 infracciones heredadas y cero en líneas cambiadas frente a origin/develop.
El comando exacto de CI sigue bloqueado por Ruby 3.4.11 frente a 3.4.4.
RSpec Rails de servicio/invitación/herramientas/recordatorios no ejecutado:
la imagen de aplicación no tiene rspec. Falta rojo/verde de esos recorridos y
CI completo; no se declara validación funcional completa. Sin cambios visuales,
capturas, migraciones ni push. Integrar PR1 → PR2 → PR3.

### B-NEW-083 — Reserva y confirmación de la cita propietaria (CIT-09 / CIT-30)

**Archivos:** `CalendarEvent`, `Integrations::GoogleCalendar::EventService`,
herramientas de citas de Captain y sus specs de servicio/herramientas.

**Fix:** una clave solo reutiliza un evento de la misma conexión, calendario e
intervalo; una colisión devuelve `InvalidRange` antes de Google. Mover el inicio
o fin libera la clave en la misma escritura del evento, también al sincronizar
un movimiento de Google. Editar sin mover conserva la clave. A→B→nueva A mantiene
el evento movido en B y permite una nueva reserva idempotente en A. Las claves
de Captain incluyen la conexión; texto y botones usan el inicio devuelto por el
evento persistido, incluida la recuperación tras fallos de notificación.

Captain lista por conexión y calendario, confirma con `find_by!` y exige la fila
local propietaria al cancelar o reprogramar. Si desaparece después del listado,
devuelve error sin llamar a Google. Se conservan los callbacks de recordatorios.
El dashboard mantiene la importación/edición/cancelación de eventos Google-only;
la exigencia de fila local corresponde al recorrido de Captain (CIT-30).

**Cómo probar:** reservar A dos veces, mover a B y reservar A otras dos veces:
solo dos eventos, cada confirmación con su hora y botones asociados al evento
correcto. Repetir con dos conexiones al mismo calendario y mismo ID Google:
solo cambia la fila propietaria. Quitar esa fila entre listado y mutación: error,
sin mutación remota. Verificar horarios de recordatorios al mover y cancelación
de pendientes al cancelar. Specs nuevos en `event_service_spec.rb` y
`appointment_tools_spec.rb`; regresión `appointment_reminders_spec.rb`.

**Verificación local:** sintaxis de los 12 archivos Ruby de la rama frente a
`origin/develop` y RuboCop directo en `chathub-rubocop-ci`, sin infracciones en
líneas nuevas. La invocación exacta de CI está bloqueada por Ruby 3.4.11 frente a
3.4.4 del Gemfile. RSpec intentado con base aislada explícita: faltan gemas de test;
no se ejecutaron ejemplos ni se acredita rojo/verde. Capturas y Google real
pendientes. Sin migraciones; depende del PR 1 (`feat/citas-autorizacion`).
Pendiente merge/deploy y validación CI; no se hizo push.

### B-NEW-082 — Asociaciones de citas sin autorización (CIT-11)

**Archivos:** `lib/integrations/google_calendar/event_service.rb`,
`app/controllers/api/v1/accounts/integrations/calendar_controller.rb`, locales en/es
y specs de integración, servicio y eventos por conversación.

**Fix:** crear, editar y cancelar autorizan `ConversationPolicy#show?` antes de
acceder a Google. Al mutar se comprueba también la conversación guardada, aunque
el cliente omita, borre o sustituya la asociación. Los retornos por idempotencia
autorizan el evento guardado. Se conserva el contexto de rol Enterprise; los bots
no resuelven membresías por un ID numérico que pueda coincidir con un usuario.
Un contacto discordante devuelve 422 localizado; IDs ajenos no se resuelven fuera
de la cuenta. Pundit conserva su 401 y los recursos inexistentes su 404.

**Cómo probar:** con un agente sin acceso al inbox, intentar crear, editar,
cancelar por DELETE y por PATCH, y sustituir/quitar las asociaciones: 401, sin
mutación Google, actividad ni mensaje. Con acceso, mezclar contacto y conversación:
422. Repetir con admin, agente miembro y AgentBot válido: recorrido permitido.
Repetir con rol Enterprise de participación, sin y con participación.

**Verificación local:** sintaxis Ruby, nueva clave en/es y nueve tests existentes
de helpers Calendar en UTC y America/Guayaquil aprobados. RuboCop en imagen
`chathub-rubocop-ci`: cinco archivos inspeccionados, cero infracciones en líneas
modificadas; 37 infracciones anteriores en los archivos completos. RSpec queda
reservado a CI; todavía no se acredita ejecución rojo/verde. Capturas pendientes:
la herramienta no dispone de navegador. Sin migraciones. Pendiente merge/deploy.

### B-NEW-081 — Cierre de variables Flow, notificaciones e importadores (MV-12, MV-13, MV-16)

**Archivos:** `Variables::{ContextFactory,Omission,ImportDiagnostics,Writer}`,
`VariablesController`, `Flows::{DeferredSendJob,ActionService,ExecutionService}`,
`AutomationNotificationMailer`, `MessageTemplates::Template::Greeting`,
`Concerns::Toolable`, `Captain::Tools::HttpTool`, `DataImportJob`,
`DataImport::ContactManager`, `DataImports::Importer` y el correo de importación.

**Fix:** el run explícito habilita `flow.x` y `flow.variables.x` en preview,
envío, notas y captura. Notificaciones resuelven `custom_message` antes de
insertarlo; herramientas HTTP comparten contexto CRM y devuelven diagnóstico
con ruta/estado. Saludos y notificaciones incompletos se omiten con nota privada.
Los snapshots se interpolan una vez, usando fechas en zona de cuenta.
API/prechat conservan su writer común y JSON literal. CSV/Intercom/Freshdesk
protegen atributos gestionados y avisan de claves sin definición, sin crear
definiciones a partir de metadata técnica ni modificar formatos de entrada.
CSV incluye el aviso en el correo; externos lo muestran en sus resultados.
Los avisos externos cuentan como incidencias, sin sumar registros ficticios.
Sin migraciones ni cambios de frontend, campañas, Meta, Panel AI o cobros.

**Cómo probar:** guardar `x` en un nodo de Flow y enviar `{{ flow.x }}` en texto
y botón; comparar preview con `flow_run_id`/`conversation_id`. Usar un run ajeno
debe devolver 404, y uno sin conversación, 422. Probar un saludo y una notificación
con `contact.identifier`, fecha y atributo ausente: solo el último se omite y
deja razón privada. HTTP con ruta CRM debe resolverla; un dato ausente impide
la petición y muestra ruta/estado. Importar una columna sin definición: el valor
se conserva y se informa su clave, nunca su valor. Crear la definición y verificar
el selector. CSV con `total_citas` protegido queda en rechazados. Repetir con
Intercom/Freshdesk; revisar avisos, contadores y que no aparezcan definiciones
automáticas. Specs Ruby preparados por superficie; ejecución integrada solo CI.

**Estado:** implementado; RSpec pendiente de CI. Comprobaciones aisladas con
Liquid reproducen MV-12/MV-13 antes y pasan después; no sustituyen Rails/RSpec.
Contrato y límites: `docs/VARIABLES_ENGINE.md`, sección de cierre PR F.

### B-NEW-080 - Captain y escritura de variables (MV-10, MV-11, MV-14)

**Archivos:** `Captain::TemplateMessage`, sus tres senders, `Captain::VariableDiagnostics`,
`Enterprise::Variables::ContextFactory`, `Variables::{Writer,Ownership,ValueNormalizer}`,
`SaveTargets`, `ActionService`, entradas API/prechat y editores de atributos.

**Fix:** mappings explicitos de Captain omiten mensajes incompletos y exponen la
ultima razon en configuracion del asistente; solo referencias sin mappings
conservan el guion legacy. Resolver/fabrica compartidos y snapshots de una sola
resolucion. El writer comun aplica propiedad Calendar/formula desde Rails a
acciones, captura Flow y API/prechat, incluido borrado/reemplazo; metadata en UI.
`multi_list` resuelve cada elemento antes de persistir. Sin migraciones.

**Como probar:** configurar una plantilla Captain con `Hola {{ contact.email }}`
y un contacto sin email: no hay envio publico, aparece la razon en ajustes;
recordatorio/reactivacion dejan nota privada. Una referencia legacy sin mappings
sigue usando el guion. Habilitar total_citas e intentar sobrescribirlo/borrarlo
por API, accion o un Flow publicado anteriormente: se rechaza/omite; actualizar
otro atributo con merge conserva total_citas. Verificar formulas de empresa.
Una accion multi_list con `{{ contact.name }}` guarda el nombre, no la expresion.
Specs Ruby por superficie preparados para CI; frontend verificado en UTC y
America/Guayaquil. Capturas pendientes por navegador de herramientas no disponible.
Alcance restante MV-12/13/16 documentado en `docs/VARIABLES_ENGINE.md`.


### B-NEW-76 — Selectores de variables divergentes y claves especiales ocultas (MV-06/07/08/09)

**Archivos:** `useVariableCatalog.js`, `templateVariableBindings.js`, `VariablePicker.vue`,
`WhatsAppTemplateParser.vue`, `TemplateFormDrawer.vue` y `Whatsapp::TemplateVariableBindingsService`.

**Fix:** plantillas, Parser, centro de envío y acciones de plantilla consumen el catálogo Rails
compartido por cuenta/superficie. El selector usa identidad de definición y expresiones literales
del servidor para claves Unicode, con punto o guion. No ofrece contextos ausentes ni derivados
Calendar/fórmulas para escritura; conserva mappings desconocidos y texto ante errores.
El servidor acepta los paths literales exactos del catálogo al guardar mappings, manteniendo
la gramática legacy. No cambia el envío. Respuestas rápidas, editor y acciones de texto quedan
pendientes bajo A10 del brief; sus listas aún tienen consumidores y se conservan.

**Cómo probar:** crear atributos `nivel-vip`, `nivel.vip` y `categoría`, insertarlos en una
plantilla y comprobar sus mappings y preview; abrir Parser desde centro de envío/nueva
conversación. Una variable de cita guardada sin contexto debe indicar «No disponible».
Interrumpir `/variables`: reintentar sin perder mappings ni texto. En Flow, verificar que los
derivados de Citas no aparecen como destino. Specs frontend y de contrato Ruby incluidos;
RSpec requiere CI/entorno aislado descrito en `docs/TESTING.md`.

### B-NEW-079 — CI del PR #178: notas de omisión y fixtures de campañas

**Archivos:** `app/services/automation_rules/action_service.rb`,
`spec/services/{sms,twilio}/oneoff_sms_campaign_service_spec.rb` y
`spec/services/variables/catalog_spec.rb`.

**Causa y fix:** Ruby 3 separa keywords del hash posicional requerido por
`leave_automation_skip_note!`; pasar el hash explícito para registrar las notas
de plantilla omitida y ventana cerrada. Los ejemplos MV-04 y de omisión SMS
quedaron fuera del setup del proveedor: moverlos dentro de `describe 'perform'`.
Twilio verifica el cliente simulado, evitando depender de la identidad de una
instancia ActiveRecord. El catálogo mantiene fechas disponibles en campañas,
como exige BRIEF-MOTOR-B A2; corregir la expectativa del contrato anterior.

**Cómo probar:** en CI ejecutar los cuatro archivos indicados. Comprobar notas
privadas al usar un canal distinto o bandeja incorrecta; fecha de Guayaquil sin
crear conversaciones; destinatarios incompletos omitidos sin llamar al proveedor.
RSpec reservado a CI; revisión estática contra el run `39508121861`.

### B-NEW-76 — Variables en envíos y campañas (MV-04, MV-05, MV-15)

**Archivos:** `Variables::DeliveryRenderer`, `Variables::Resolver`,
`Whatsapp::Flows::SendFlowService`, adaptadores de campañas WA/SMS/web,
`AutomationRules::ActionService`, `Liquidable` y `Messages::MessageBuilder`.

**Fix:** resolver compartido antes del transporte; snapshot de Flow coherente
con el historial y persistido antes de encolar. Fechas de campaña en zona de
cuenta. Datos ausentes/invalidos omiten destinatarios con ruta y estado en el
registro de campaña; acciones de plantilla dejan nota privada en inglés/español.
Avisos web públicos excluyen mensajes que requieren contacto; solo al crear
la conversación se resuelven datos personales. Sin migraciones ni conversaciones
al enviar campañas WA/SMS. Adaptador histórico Enterprise conserva alias Meta.

**Cómo probar:** Flow con `Hola {{ contact.name }}` en body/header/CTA;
comprobar payload Cloud e historial. Campaña WA/SMS con `date.today` cerca de
medianoche UTC y cuenta America/Guayaquil; comprobar día anterior. Destinatario
sin email en texto mixto: ningún envío, registro skipped con razón. Aviso web
con cuenta/fecha resuelto; con contacto no aparece en la respuesta pública y
se resuelve al crear conversación. Acción plantilla con appointment.title sin
contexto: solo nota privada. Specs preparados por superficie; RSpec solo en CI.
Envío manual y selector quedan con el contrato previo hasta PR C.

### B-NEW-75 — Preview de variables distinto del envío (MV-01, MV-02, MV-03)

**Archivos:** `Variables::Catalog`, `Variables::ContextFactory`, `Variables::Resolver`,
`VariablesController`, `Liquidable`, `ContactDrop`, `DateDrop` y `WhatsAppTemplateParser.vue`.

**Fix:** Rails calcula el preview por lote con los mismos Drops del mensaje:
columna de documento/país, capitalización y apellido de contacto, nombre interno
del agente. Un nombre no informado devuelve apellido vacío, como UserDrop,
sin lanzar un error al consultar el dato. Los parámetros sin editar conservan Liquid. Catálogo por cuenta con
claves literales y metadata de propiedad. Fechas de mensajes y preview usan la
zona de la cuenta; sin configuración conservan la zona Rails anterior.

**Cómo probar:** seleccionar una plantilla con documento solo en columna, nombre
MARÍA del CARMEN, país EC y agente con nombre público diferente; comprobar preview
y mensaje. El documento no debe quedar vacío ni el país tomar country_code de
additional_attributes. Editar un campo fija el texto. Probar contacto sin dato,
fallo de preview y cuenta ajena. Contrato y comandos en `docs/VARIABLES_ENGINE.md`.
Specs Ruby preparados para CI; regresión frontend comprobada contra el parser
anterior y corregido. Sin migraciones ni cambios de transporte.


### B-NEW-74 — Registro y onboarding: contraseña, progreso y contraste

**Archivos:** registro/verify-email de `v3`, `PasswordRequirements.vue`,
`OnboardingShell.vue`, vistas de negocio/WhatsApp/asistente y
`DropdownMenu.vue`; traducciones EN/ES y sus specs.

**Fix:** separar registro y confirmación del progreso de cuatro pasos;
reflejar el rango real de contraseña (6–128) también en validación y campo;
corregir contraste de placeholders, búsqueda y acciones; mantener el pie
fuera del contenido desplazable. Ubicación automática con selectores si
falta detección; las regiones de idioma como `419` no se envían como país.
Plan es un marcador del frontend, sin precios inventados ni cambios al
cursor backend. Volver a Negocio permite consultar sus datos guardados.

**Cómo probar:** crear cuenta por correo o Google, confirmar y continuar
por Negocio → WhatsApp → Asistente → Plan. Cambiar nombre/rubro y comprobar
la vista previa; abrir Cambiar y buscar un país; omitir WhatsApp; guardar
un borrador y probarlo sin activarlo; recargar Plan antes de finalizar.
Comprobar 1366×768, móvil de 390 px y modo oscuro. La confirmación/OAuth
con proveedores reales requiere el entorno configurado del producto.

**Validación local:** pruebas frontend y capturas con componentes reales;
evidencia detallada en `tmp/BUILD-ONBOARDING.md`. Sin backend ni migraciones.

### B-NEW-65 — Citas: correcciones visuales y de edición de FASE 2 A+B v2

**Archivos:** `CalendarView.vue`, `WeekGrid.vue`, `EventBlock.vue`,
`AgendaSidebar.vue`, `calendarGrid.js`, `calendarTime.js`, `EventService`,
`CalendarController`, textos EN/ES y sus specs. Se retira la safelist añadida a
`tailwind.config.js`, que queda igual a HEAD.

**Fix:** control de cancelados junto a la leyenda y cabecera sin wrapping desde
1280 px; grilla sin bandas alternadas, con líneas horarias sutiles; dos/tres
carriles muestran nombres truncados sin hora ni prefijo repetido y tooltips
completos. Geometría inline por minuto, sin miles de clases globales. El horario
se exige al crear o mover; editar nota/estado sin mover funciona fuera del
horario vigente. Editar una cancelada devuelve un error propio localizado (422).

**Cómo probar:** abrir/activar/cerrar el control de cancelados a 1280 px en
claro/oscuro; comparar dos/tres citas simultáneas y sus tooltips. Cambiar horario
y días del calendario, editar una cita existente sin moverla y luego intentar
moverla fuera de disponibilidad, con agente y AgentBot. Editar una cancelada y
comprobar “La cita está cancelada y no se puede editar.” sin llamar a Google.
Cobertura por punto y archivos en [`CITAS_FASE2_AB.md`](CITAS_FASE2_AB.md).

**Validación local:** ESLint de toda la entrega sin errores (17 advertencias),
compilación de ocho SFC, helpers directos y generación Tailwind correctos.
Vitest no arranca por `spawn EPERM` de esbuild; RSpec/RuboCop pendientes porque
no hay Ruby local ni Docker disponible. Smoke visual/E2E pendiente del PM.

### B-NEW-64 — Citas: disponibilidad, estados, cancelación y solapes (FASE 2 A+B)

**Hallazgos:** CIT-03/10/05/04/01/18/23/24/25; refresco local de próxima cita relacionado con CIT-16.

**Archivos:** `CalendarController`, `EventService`, `CalendarEvent` y su overlay
Enterprise, `Calendar::AppointmentAttributes::Updater`; componentes del calendario,
lista/tarjeta de conversación y `ContactPanel`; helpers de estado, geometría,
tiempo y visibilidad; `tailwind.config.js`; textos EN/ES y specs correspondientes.

**Fix:** exigir días/horas para humanos y bots; rechazar estado/tipo/transición
inválidos antes de Google; PATCH cancelled y DELETE comparten cancelación con
motivo, eliminación lógica y estado cancelled. Ocupación, atributos, próxima
cita y recordatorios Captain excluyen también cancelaciones antiguas sin
deleted_at. Modal con ComboBox de estado e historial; carriles estables para
solapes con escala por minuto, paleta común y cancelados por cuenta.

**Cómo probar:** crear/mover dentro y fuera de horario con agente y AgentBot;
enviar tipos/estados inválidos; cancelar con PATCH y DELETE, comprobando motivo,
Google, atributos, tarjeta y recordatorios. Mostrar dos/tres eventos simultáneos,
adyacentes y cancelados en semana, agenda, móvil y conversación. Cambiar de
cuenta y comprobar preferencias separadas. Comandos, cobertura y límites en
[`CITAS_FASE2_AB.md`](CITAS_FASE2_AB.md).

**Validación local:** ESLint sin errores; compilación Vue, comprobaciones directas
de helpers con Node y generación de utilidades Tailwind. RSpec, RuboCop, Vitest y
smoke visual/E2E pendientes. No hay migraciones. Seguimiento externo Panel AI y
reconciliación Google permanecen fuera de alcance.

### B-NEW-63 — Template drawer picker lists displaced the form (PR Z)

**Files:** `settings/templates/TemplateFormDrawer.vue`, `TemplateComboBox.vue`,
`components-next/combobox/ComboBox.vue` and their specs.

**Symptom:** opening language, header, inbox or variable lists inserted a static
menu into the drawer's scroll area and pushed subsequent fields down.

**Fix:** remove the template wrapper's in-scroll portal. The drawer provides its
scroll viewport as a shared ComboBox boundary; its pickers (including nested copy
mappings) teleport fixed lists to the body. Lists flip above when more space is
available there and scroll internally within a 320px cap, above the fixed footer.
Escape restores trigger focus without scrolling. Consumers without a drawer
boundary retain their existing portal behavior; the create-attribute CTA remains.

**How to check:** open a fully populated, scrolled new/copy/edit drawer at
1440x900 and 1100x700 in light/dark themes. Compare the next field's
`getBoundingClientRect().top` before/after opening each enabled picker: unchanged.
Check the footer stays clickable, Escape/outside close the list without changing
scroll, and creating an attribute still opens the existing modal. Regression
specs assert the portal is outside the scroll area and the list is fixed.

> Documento vivo. Cada bug tiene ID, severidad, archivo, descripción, fix aplicado
> y cómo probarlo. Trazabilidad cruzando con `INTERNAL_TASKS_AND_ALERTS.md`.

### B-NEW-53 — Flow: tarjeta vacía por contrato de respuestas incorrecto (2026-10-07)

**Archivos:** `components-next/message/MessageList.vue`,
`bubbles/WhatsappFlowResponse.vue`, `helpers/whatsappFlowResponse.js`,
`whatsapp/flows/send_flow_service.rb`, `whatsapp/flows/save_response_service.rb`.

**Síntoma:** la tarjeta esperaba `responseJson`, pero el backend entrega
`content_attributes.whatsapp_flow_response` plano; no mostraba filas ni copia.

**Fix:** conservar las claves originales del payload plano y agregar metadata
separada desde el snapshot saliente validado. Mostrar etiquetas, títulos de
opciones y archivos como texto; copiar respuestas con nombre del Flow y feedback.
El mapeo `save_to` y el fallback TextBubble de mensajes antiguos se conservan.

**Cómo probar:** completar un Flow con selección múltiple, texto largo y archivo;
verificar seis filas legibles en claro/oscuro, “Archivo recibido” sin enlace,
“Copiar respuestas” con texto `Etiqueta: valor` y “Copiado”. Sin metadata, esperar
encabezado Flow y etiquetas humanizadas; mensajes antiguos siguen como texto.
Vitest: 3 archivos, 12 pruebas aprobadas. Specs de metadata y guardado agregados;
RSpec pendiente de CI porque el contenedor local no tiene el ejecutable.

**Última actualización:** feature `B-NEW-52` time automations before/on/after
(2026-08-14). Antes: feature `B-NEW-51` `contacts.chat_bot` + Panel reclaim AgentBot
(2026-07-29). Antes: feature `B-NEW-50` business rules lint + dry-run + kill switch
(2026-07-29). Antes: fix `B-NEW-49` KPIs contacto open/resolved (enum group keys)
(2026-07-29). Antes: fix `B-NEW-48` contact search doble encode + ILIKE
(2026-07-28, branch `feat/contact-ui-overhaul`). Antes: hotfix `B-NEW-47` modal resolve precarga + * + rojo
(2026-07-28). Antes: hotfix `B-NEW-46` cadena de business rules en modal resolve
(2026-07-28). Antes: hotfix `B-NEW-45` resolve `.map` business rules
(2026-07-28). Antes: feature `B-NEW-44` automation timeline tuerca + actividades
(2026-07-28). Antes: hotfix `B-NEW-43` franja Panel IA pegada con humano
(2026-07-27). Antes: feature `B-NEW-42` flows explicit next + step preview
(2026-07-27). Antes: `B-NEW-41` flows canvas layout persistente (2026-07-27).
Antes: hotfix `B-NEW-40` WA template vars (`findComponentByType`) (2026-07-27).
Antes: hotfix `B-NEW-39` skip outbound si ventana Meta/WA
cerrada (2026-07-27). Antes: feature `B-NEW-38` automation audit private note
(2026-07-27). Antes: hotfix `B-NEW-37` select fecha/datetime en
time automation schedule (2026-07-27). Antes: hotfix `B-NEW-36` exigir agente humano + selector
contacto transparente (2026-07-27). Antes: hotfix `B-NEW-35` BR guard skip
en automations (2026-07-27). Antes: hotfix `B-NEW-34` motivo al posponer (nota FE +
snooze errors) (2026-07-27). Antes: hotfix `B-NEW-33` dialog BR submit
accidental (MultiSelect type=button) (2026-07-27). Antes: feature `B-NEW-32`
business rules ConditionRow + categorías + multi-status (2026-07-27). Antes:
feature `B-NEW-31` business rules contact attrs + zero-as-blank + TYPE_HELP
(2026-07-27). Antes: hotfix `B-NEW-30` toggle_status 500
(`activity_message_params` kwargs) + resolve modal currency/percent (2026-07-27).
Antes: hotfix `B-NEW-29` dashboard JS post-4.16.1
(`hasFilteredUnreadCounts` / `useI18n`) (2026-07-26). Antes: hotfix
`B-NEW-28` api_and_webhooks (login 500 post 4.16.1) (2026-07-26). Antes:
polish `B-NEW-26` flows layout/acciones/i18n
(2026-07-24). Antes: fix `B-NEW-25` flows actions cards/dropdown clip
(2026-07-24). Antes: polish `B-NEW-24` flows lista/categoría/drawer/inspector
(2026-07-24). Antes: polish `B-NEW-23` flows editor layout/perf/buttons
(2026-07-24). Antes: fix `B-NEW-22` flows canvas + handoff note legible
(2026-07-24). Antes: `B-NEW-20` report panel full-scan (aggregation +
flat CA measures) (2026-07-24, branch `fix/report-panels-correctness`). Antes:
`B-NEW-19` pivot name/rank = 0 + fila Sin asignar
(2026-07-24, branch `fix/report-panels-pivot-identity`). Antes:
`B-NEW-13` report panel pivot collapsing agent
rows (2026-07-23, branch `fix/report-panels-pivot-agent-rows`). Antes:
`B-NEW-12` WhatsApp Flow nfm_reply. Auditoría previa pre–chats grupales
(2026-07-11), branch `feat/internal-tasks` (PR #3).

---

## 0. Gate: listo para chats grupales internos?

**Veredicto: GO (condicional)**

| Criterio | Estado |
|----------|--------|
| Ningún P0 abierto | ✅ CABLE-TASK-01 + TASK-DESTROY-01 fijados |
| P1 privacidad/ACL/claim | ✅ TASK-CLAIM-01, TASK-SCOPE-01, NOTE-PRIV-01 fijados |
| Smoke 2 browsers realtime | ⚠️ Verificar manualmente tras rebuild (claim 409 FE + cable scoped) |
| P2 no bloqueantes | Abiertos a propósito (validaciones assignee, status libre) |

**Shared infra notes (para diseñar grupales):**

1. ActionCable de tasks ya no hace fan-out a todos los agents — reutilizar el patrón `internal_task_agents` / policy scope.
2. Notas privadas: reglas unificadas en `Conversations::PrivateNoteVisibility` (timeline + MessageFinder + broadcast). Sustituir por `NotePolicy` cuando exista.
3. Presence / `staleThreshold` en `node_modules` sigue sin patch (ops/proxy).
4. Migración 20260711* pendiente de aplicar en cada entorno (`db:migrate`).

---

## 1. Resumen de fixes

| ID | Severidad | Bloquea grupales? | Estado |
|----|-----------|-------------------|--------|
| TASK-001 | Alta | No (timeline) | ✅ Fijado (refactor → PrivateNoteVisibility) |
| TASK-002 | Alta | No | ✅ Fijado |
| TASK-003 | Media | Parcial | ✅ Mejorado con `with_lock` + FE 409 |
| TASK-004 | Media | No | ✅ Fijado |
| TASK-005 | Baja | No | ❌ **Era falso positivo — revertido**: `currentChat` **sí se usa** en TaskDetail.vue:61 y en TaskDetailConversation.vue. Mi reporte original del 2026-07-11 estaba MAL. Removida la entry. |
| UX-001 / UX-002 | Media | No | ✅ Fijado |
| CABLE-TASK-01 | P0 | **Sí** | ✅ Confirmado + fijado |
| TASK-DESTROY-01 | P0 | **Sí** | ✅ Confirmado + fijado |
| TASK-CLAIM-01 | P1 | Sí | ✅ Confirmado + fijado |
| TASK-SCOPE-01 | P1 | Sí | ✅ Confirmado + fijado |
| NOTE-PRIV-01 | P1 | Sí | ✅ Confirmado + fijado |
| B-NEW-01 | Media | No | ✅ Fijado — `InternalTaskEvent#broadcast_task_activity` sin doble dispatch |
| B-NEW-02 | Media | No | ✅ Fijado — guard de bot/Conversation en `resolve_agent` |
| B-NEW-03 | Media | No | ✅ Fijado — `MessageFinder#apply_private_note_visibility` null-safe |
| B-NEW-04 | Baja | No | ✅ Fijado — orden de filas en `ContactInfo.vue` consolidado |
| B-NEW-05 | Baja | No | ✅ Revisado — `v-if` ya cubre el caso; sin cambio necesario |
| B-NEW-09 | 🔴 Media → reclasif. ✅ | No (drift) | ✅ Investigado — migración ya existía; `schema.rb` queda con la columna |
| B-NEW-10 | Baja | No | ✅ Fijado — type-check en `AssignDefaultAgentService#perform` |
| TASK-006 | Baja | No | panel-ai (fuera de alcance Chatwoot) |
| TASK-007 | Baja | No | ContactInfo mojibake — abierto |
| TASK-008 | Baja | No | **Stale** — índice `[:account_id, :active, :position]` ya existe |
| B-NEW-11 | Media | No | ✅ Re-fijado (2026-07-21) — regresión en `d54c4092d` revirtió attended; restaurado en `feat/automation-formulas-and-date-vars` |
| B-NEW-12 | Media | No | ✅ Fijado — Flow nfm_reply: i18n restaurado + sin confirmación outbound al cliente |
| B-NEW-13 | 🔴 Alta (prod) | No | ✅ Fijado — pivot summary rows seeded from flat summary; no more agent collapse |
| B-NEW-19 | 🔴 Alta (prod) | No | ✅ Fijado — pivot name/rank no longer clobbered to 0; Sin asignar row |
| B-NEW-20 | 🔴 Alta (prod) | No | ✅ Fijado — aggregation + flat CA measures full-scan (no 100/2000 cap) |
| B-NEW-21 | Media | No | ✅ Fijado — panel `date_attribute` + NumericParser + filter UX |
| B-NEW-14 | Feature | No | ✅ Business rules + time automations + multi_list (branch `feat/business-rules-time-multilist`) |
| B-NEW-15 | Flows UI | Baja | ✅ Portado a `feat/business-rules-time-multilist` (model/API/UI/`flows_v1`) |
| B-NEW-16 | 🔴 P0 | No | ✅ Time-rule ledger: conditions before claim + hours window_id from message id/created_at |
| B-NEW-17 | Feature | No | ✅ P0 CRM unlock: time-rule CA actions + relative dates + seguimiento_30d + safe date SQL |
| B-NEW-18 | Smoke | No | ✅ Local Docker smoke: VPS DFIT attrs + seguimiento_30d on `fecha_seguimiento` (conv #154) |
| B-NEW-22 | Flows UX | Baja | ✅ Canvas Vue Flow + nota handoff legible (sin IDs técnicos) |
| B-NEW-23 | Flows UX | Baja | ✅ Polish: full-bleed, footer exit, botones opcionales, títulos, perf |
| B-NEW-24 | Flows UX | Baja | ✅ Activo en lista, categoría, exit drawer, inspector compacto |
| B-NEW-25 | Flows UX | Baja | ✅ Acciones numeradas en cards; dropdown sin clip por overflow |
| B-NEW-26 | Flows UX | Baja | ✅ Acciones horiz., tipos únicos, menubar, panel izq, i18n es |
| B-NEW-28 | 🔴 P0 prod | Sí | ✅ Login 500: faltaba `api_and_webhooks` en features.yml ext_1 |
| B-NEW-29 | 🔴 P0 prod | Sí | ✅ Dashboard JS: `hasFilteredUnreadCounts` + `useI18n` imports |
| B-NEW-30 | 🔴 P0 prod | Sí | ✅ toggle_status 500: `activity_message_params` + modal currency/percent |
| B-NEW-31 | Feature | No | ✅ Business rules: contact attrs + zero-as-blank + TYPE_HELP |
| B-NEW-32 | Feature | No | ✅ Business rules UX: ConditionRow + categorías + multi-status (sin tab tiempo) |
| B-NEW-33 | Bug UX | No | ✅ Dialog BR: MultiSelect/ConditionRow buttons type=button (no submit accidental) |
| B-NEW-34 | Bug UX | No | ✅ Motivo al posponer: FE no bloquea nota a ciegas; snooze con errores BR |
| B-NEW-35 | Bug | No | ✅ BR Guard no bloquea cambios de status hechos por AutomationRule |
| B-NEW-36 | Bug | No | ✅ Exigir assignee = humano/equipo (bot no cuenta); ContactAssignee dropdown |
| B-NEW-37 | UX | No | ✅ Time automation: select CA fecha/datetime (no input libre) |
| B-NEW-38 | Feature | No | ✅ Automation siempre deja nota privada corta de auditoría |
| B-NEW-39 | Bug | No | ✅ Automation no envía outbound si `can_reply?` false (ventana 24h) |
| B-NEW-40 | 🔴 P0 prod | Sí | ✅ WA templates: `findComponentByType is not defined` → sin inputs + crash al enviar |
| B-NEW-41 | Flows UX | Baja | ✅ Canvas: posiciones persistentes, no re-dagre, connect por handle |
| B-NEW-42 | Flows UX | Media | ✅ Rutas explícitas `step.next` + overview ℹ️ del flujo |
| B-NEW-43 | Bug UX | No | ✅ Franja Panel IA se oculta con assignee humano; limpia `panel_ia_*` + leyenda Bots/Flows |
| B-NEW-44 | Automation UX | No | ✅ Sin nota audit genérica; tuerca en outbound; activity con nombre de regla |
| B-NEW-45 | 🔴 Bug UX | No | ✅ Resolve crash: `condition.values` scalar → `.map is not a function` |
| B-NEW-46 | Bug UX | No | ✅ Modal resolve encadena reglas al cambiar attrs (ej. tipo=Venta → pide Y/Z) |
| B-NEW-47 | Bug UX | No | ✅ Modal resolve precarga valores, `*` obligatorio, faltante en rojo al abrir |
| B-NEW-48 | Bug UX | No | ✅ Contact search: sin doble encode; ILIKE id/doc; company_name |
| B-NEW-49 | Bug UX | No | ✅ KPIs contacto: normalizar keys de `group(:status)` (open/resolved) |
| B-NEW-50 | Feature | No | ✅ BR safety: lint al activar, dry-run FE, `business_rules_paused`, enabled default false |
| B-NEW-52 | Feature | No | ✅ Time automations: N días antes / el mismo día / N días después del atributo |

---

## 2. Auditoría 2026-07-11 — P0/P1 fijados

### CABLE-TASK-01 — Broadcast de tasks a todos los agents

**Confirmado.** `internal_task_created/updated` usaba `account.agents`.

**Fix:** `internal_task_agents` alinea con `InternalTaskPolicy::Scope` (pool abierto → todos; si no → assignee + miembros del team). Admins siguen vía `user_tokens`.

**Archivo:** `app/listeners/action_cable_listener.rb`

### TASK-DESTROY-01 — Soft-cancel siempre 403

**Confirmado.** `destroy?` no existía → `ApplicationPolicy#destroy?` → `false`.

**Fix:** `destroy?` = `update?` en `InternalTaskPolicy`.

### TASK-CLAIM-01 — Race + FE sin 409

**Confirmado.** Check-then-update sin lock; store no manejaba conflict.

**Fix:** `with_lock` + `reload` en `ClaimService`; store refresca en 409; `useInternalTaskActions` muestra alert.

### TASK-SCOPE-01 — Tasks de conversación / timeline sin ACL

**Confirmado.** Nested index usaba `@conversation.internal_tasks` sin `policy_scope`; timeline listaba todos los task events.

**Fix:** `policy_scope` en nested controller; timeline filtra `visible_task_ids` por Scope.

### NOTE-PRIV-01 — Hilo vs timeline divergentes

**Confirmado.** Timeline filtraba; `MessageFinder` y ActionCable de notas privadas no.

**Fix:** `Conversations::PrivateNoteVisibility` compartido; MessageFinder (dashboard) + `message_broadcast_members` en cable.

### Extra (P2 mínimo)

- Comentarios de task: eliminado doble `dispatch_updated_event` (solo `touch`).
- Index de tasks: `includes(:events)` para N+1 del jbuilder.

---

## 2.1. Segunda pasada de revisión (2026-07-11 tarde)

Después de aplicar los fixes P0/P1, se hizo otra pasada detectando bugs adicionales.

### B-NEW-01 — `InternalTaskEvent#broadcast_task_activity` causaba doble dispatch

**Severidad:** Media — causaba dos broadcasts por cada evento (excepto `created`).
`touch` ya dispara `after_update_commit → dispatch_updated_event`; la llamada extra
a `internal_task.dispatch_updated_event` producía el doble.

**Fix:** eliminado el `dispatch_updated_event` redundante dentro de
`broadcast_task_activity`.

**Archivo:** `app/models/internal_task_event.rb`

```ruby
def broadcast_task_activity
  # touch bumps updated_at and fires after_update_commit → dispatch_updated_event once
  internal_task.touch
end
```

### B-NEW-02 — `AssignDefaultAgentFromFirstReplyService` podía asignar no-Users

**Severidad:** Media — `resolve_agent` retornaba `message.conversation.assignee`
sin type-check. Si assignee era un Bot o Conversation, `update!(assigned_agent: ...)`
crasheaba con `ActiveModel::TypeMismatch`.

**Fix:** narrowed a User con `id.present?`, además de los guards en `perform`.

**Archivo:** `app/services/contacts/assign_default_agent_from_first_reply_service.rb`

```ruby
def resolve_agent
  sender = message.sender
  return sender if sender.is_a?(User) && sender.id.present?

  assignee = message.conversation&.assignee
  return assignee if assignee.is_a?(User) && assignee.id.present?

  nil
end
```

### B-NEW-03 — `MessageFinder` fallaba sin `Current.user`

**Severidad:** Media — procesos background (Sidekiq, exports, scripts sin
sesión) terminaban con `list.select` filtrando TODO mensaje privado
(incluyendo notes que sí vería un humano en sesión).

**Fix:** si `Current.user` es blank, retornar la lista sin filtrar (visibilidad
permisiva para procesos background). Además, inferir `conversation` desde el
primer mensaje si `@conversation` no está seteado.

**Archivo:** `app/finders/message_finder.rb`

```ruby
def apply_private_note_visibility(message_list)
  list = Array(message_list)
  return list if Current.user.blank?
  return list if ActiveModel::Type::Boolean.new.cast(@params[:filter_internal_messages])

  conversation = @conversation || list.first&.conversation
  return list if conversation.blank?

  list.select do |message|
    !message.private? || Conversations::PrivateNoteVisibility.allowed?(
      user: Current.user, message: message, conversation: conversation
    )
  end
end
```

### B-NEW-04 — Layout de `ContactInfo.vue` partía los datos en dos bloques

**Severidad:** Baja — el refactor había dejado `phone + documentNumber` en un
bloque (junto al avatar) y `email + identifier + company + location` en otro
debajo, partiendo la info de contacto arbitrariamente.

**Fix:** consolidados todos los `ContactInfoRow` en una sola columna,
con orden lógico: email → phone → identifier → document → company → location.

**Archivo:** `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue`

### B-NEW-05 — `Avatar` huérfano cuando `showAvatar=false`

**Severidad:** Baja — revisado, no requirió cambio. El `<Avatar>` ya tenía
`v-if="showAvatar"`; el wrapper `flex flex-row items-start gap-3` no genera
espacio visual fuerte cuando el Avatar está oculto (gap con un hijo sigue
siendo razonable).

**Estado:** ❌ No aplicado. Sin cambio necesario.

### B-NEW-09 — `db/schema.rb` drift vs migración ya aplicada

**Severidad:** Media — preocupado al inicio como Alta, **reclasificado tras verificación**.

**Investigación:** al intentar `rails db:migrate` reaplicar la columna, Rails
reportó `DuplicateMigrationNameError` con la migración `20260630120000_add_assigned_agent_id_to_contacts.rb`
(ya existente en `db/migrate/` y aplicada según `schema_migrations`). La columna
`contacts.assigned_agent_id`, su índice `index_contacts_on_assigned_agent_id` y
la FK a `users(id)` **ya estaban presentes en la BD**.

**Conclusión:** la edición manual de `db/schema.rb` era una corrección de drift
(no agregaba nada nuevo), no una migración faltante. Mi diagnóstico inicial fue
incorrecto — el `db/schema.rb` modificado **debe quedarse** (refleja el estado
real de la BD). No creo nueva migración.

**Verificación en BD local:**
```sql
\d contacts
-- assigned_agent_id | bigint | (presente)
-- index_contacts_on_assigned_agent_id btree (assigned_agent_id)
-- fk_rails_cded5b5676 FOREIGN KEY (assigned_agent_id) REFERENCES users(id)
```

**Acción:** revertí mi migración duplicada (`20260711120000`) y mantuve el
`schema.rb` con la columna.

**Aprendizaje:** antes de declarar "falta migración", correr
`SELECT version FROM schema_migrations`. Si el timestamp figura, **la
migración YA está aplicada** aunque el `schema.rb` estuviera desactualizado.
El "fix" entonces es regenerar `schema.rb` con `rails db:schema:dump`, no
crear migración nueva.

**Estado:** ✅ Documentado y corregido.
Migración `db/migrate/20260711120000_add_assigned_agent_id_to_contacts.rb` borrada.

### B-NEW-10 — `Contact.update!` con type-check insuficiente

**Severidad:** Baja — defensa explícita en `AssignDefaultAgentService#perform`
para no asignar un agente inválido al contacto (Bot, Conversation, etc.).

**Fix:** agregado `return unless agent.is_a?(User)` y `return if agent.id == contact.id`
(previene self-assignment).

**Archivo:** `app/services/contacts/assign_default_agent_from_first_reply_service.rb`

```ruby
def perform
  return unless message.human_response? && !message.private?

  contact = message.conversation&.contact
  return if contact.blank?
  return if contact.assigned_agent_id.present?

  agent = resolve_agent
  return if agent.blank?
  return unless agent.is_a?(User)
  return if agent.id == contact.id

  contact.update!(assigned_agent: agent)
end
```

### B-NEW-11 — Automation replies no marcaban la conversación como attended

**Severidad:** Media — afecta reporting (`Unattended`/`Unassigned` counts en `LiveReports`) y SLA. Bug latente en cualquier cuenta que use automatizaciones (`AutomationRules::ActionService#send_message`) o macros con `send_message`.

**Síntoma:** una automatización que responde automáticamente a un cliente no limpiaba `conversation.waiting_since` ni seteaba `conversation.first_reply_created_at`. La conversación quedaba en el bucket "Unattended" aunque la respuesta ya se había enviado y entregado.

**Causa raíz:**

`Message#human_response?` (`app/models/message.rb:371`) tenía esta firma:

```ruby
def human_response?
  outgoing? &&
    content_attributes['automation_rule_id'].blank? &&   # bloqueaba automation
    additional_attributes['campaign_id'].blank? &&
    (sender.is_a?(User) || content_attributes['external_echo'].present?)
end
```

Cuando una automation corría vía `AutomationRules::ActionService#send_message` (`app/services/automation_rules/action_service.rb:46`), creaba el `Message` con:
- `content_attributes: { automation_rule_id: @rule.id }` ← bloqueaba el chequeo
- `sender = nil` (porque `MessageBuilder.new(nil, ...)`)

Resultado: `human_response?` → `false` → `valid_first_reply?` → `false` → no se disparaba `FIRST_REPLY_CREATED`, no se limpiaba `waiting_since`, no se asignaba agente default.

Bug secundario encontrado durante el fix: `valid_first_reply?` (línea 224) tenía un **off-by-one**. El filtro era:

```ruby
return false if conversation.messages.outgoing
                            .where.not(sender_type: [...])
                            .where.not(private: true)
                            .where("(additional_attributes->'campaign_id') is null")
                            .count > 1
```

Como `valid_first_reply?` corre **dentro del after_save** (`dispatch_create_events`, línea 387), el mensaje actual ya está persistido cuando se cuenta. Con `count > 1`, **cualquier segundo outgoing no-bot ya impedía que se setee `first_reply_created_at`** — incluso respuestas legítimas de agentes humanos en una conversación con respuestas previas.

**Fix aplicado:**

1. **`Message#human_response?`** — simplificado a la regla de negocio real: cualquier respuesta saliente del sistema cuenta como respuesta, excepto notas privadas y campañas outbound (que son outreach masivo, no replies).

   ```ruby
   def human_response?
     outgoing? && !private? && additional_attributes['campaign_id'].blank?
   end
   ```

   Cobertura post-fix:
   - ✅ Mensajes de agente humano → cuentan (igual que antes)
   - ✅ Mensajes de AgentBot / Captain → cuentan (ya estaban)
   - ✅ Eco del canal (WhatsApp echo, Instagram echo) → cuentan (igual que antes)
   - ✅ Automation salientes → cuentan (**antes NO**)
   - ❌ Notas privadas → no cuentan
   - ❌ Campañas outbound → no cuentan

2. **`Message#valid_first_reply?`** — fix off-by-one: excluye el message actual (`where.not(id: id)`) y threshold `count.positive?` en vez de `count > 1`.

**Archivos tocados:**

- `app/models/message.rb` (líneas 224-233 y 371-380)
- `spec/models/message_spec.rb` (líneas 228-236) — el test "does not update first reply if sent by automation" se invirtió a "updates first reply if sent by automation" reflejando la nueva semántica

**Migración BD:** no requerida (cambia solo lógica del modelo).

**Verificación end-to-end** (smoke test contra BD del contenedor):

```
After automation reply:
  first_reply_created_at: SET ✓
  waiting_since: nil ✓
  matches unattended scope? false ✓
  human_response? true ✓

Negative cases:
  campaign message → human_response? false ✓
  private message  → human_response? false ✓
  incoming message → human_response? false ✓

Eventos disparados:
  first.reply.created ✓
  reply.created ✓
  conversation.updated (con first_reply_created_at + waiting_since cleared) ✓
```

**Cómo probar en navegador:**

1. Hard refresh (Ctrl+Shift+R).
2. Settings → Automations → crear/editar una rule de `message_created` → acción `Send a Message`.
3. Disparar un mensaje entrante en una conversación donde la automation aplique.
4. Verificar en el chatlist:
   - La conversación **sale del filtro "Unattended"** (`Unattended count` baja).
   - Aparece en "Attended".
   - `conversation.first_reply_created_at` queda seteado al timestamp del reply de automation.

**Aprendizaje / nota arquitectónica:**

El filtro `human_response?` se usaba como "single source of truth" para first-reply semantics. Tener un campo técnico (`content_attributes['automation_rule_id']`) bloqueando el reconocimiento de un reply fue un acoplamiento accidental. La regla correcta es semántica: **es un reply del sistema si sale hacia el contacto y no es nota privada ni campaña**. El flag `automation_rule_id` se mantiene en `content_attributes` para trazabilidad, pero no debe afectar el lifecycle de la conversación.

`automation_rule_id` queda en `content_attributes` por compatibilidad con los specs existentes en `spec/listeners/automation_rule_listener_old_spec.rb` (líneas 629, 731-732). Si en el futuro se quisiera unificar con `additional_attributes` (donde está `campaign_id`), es un cambio de trazabilidad, no de comportamiento.

**Estado:** ✅ Fijado originalmente (2026-07-20). **Regresión:** el commit
`d54c4092d` (`fix(conversations): resolve toggle_status I18n and keep agent-only first-reply semantics`)
revirtió `human_response?` a solo `User` + excluyó `automation_rule_id` de nuevo
en `valid_first_reply?` (el hotfix de toggle_status/I18n de ese commit es legítimo
y no se toca). **Re-fijado** 2026-07-21 en `feat/automation-formulas-and-date-vars`:
restaurar `human_response?` amplio (agent + automation + bot/echo; excluye private
y campaigns) y quitar el filtro `automation_rule_id` de `valid_first_reply?`,
conservando el off-by-one (`where.not(id: id)` + `count.positive?`).

Decisión de producto (aprobada): automation e IA/AgentBot/Captain cuentan como
attended igual que un agente; colores de burbuja siguen familia bot (iris);
private notes y campaigns no cuentan.

### B-NEW-12 — WhatsApp Flow nfm_reply: i18n perdido + confirmación enviada al cliente

**Severidad:** Media — el agente ve `Translation missing` y el cliente recibe un resumen
técnico (a veces con keys rotas) que debía ser solo interno.

**Síntoma:**

1. Tras completar un Flow, el bubble incoming muestra
   `Translation missing: en.conversations.messages.whatsapp.flow_response.received`.
2. Se crea un outgoing que WhatsApp entrega al contacto con header/footer también
   como `Translation missing` + los campos del form.

**Causa raíz:**

- Keys `conversations.messages.whatsapp.flow_response.*` se agregaron en `23ce702b1`
  y se borraron por accidente en `34d714fbb` (export de contactos).
- `Whatsapp::FlowConfirmationService` creaba `message_type: :outgoing` sin
  `private: true` → `SendReplyJob` lo enviaba al canal.

**Fix aplicado:**

1. Restaurar `flow_response.received` / `flow_response.empty` en `config/locales/en.yml`.
2. Eliminar auto-confirmación al cliente (`send_flow_confirmation`,
   `FlowConfirmationService`, `format_confirmation`). El incoming ya guarda texto
   legible + `content_attributes['whatsapp_flow_response']`.

**Archivos:**

- `config/locales/en.yml`
- `app/services/whatsapp/incoming_message_base_service.rb`
- `app/services/whatsapp/flow_response_formatter.rb`
- `app/services/whatsapp/flow_confirmation_service.rb` (eliminado)
- specs correspondientes

**Migración BD:** no requerida.

**Cómo probar:**

1. Enviar template/Flow → cliente completa.
2. Inbox: un bubble incoming con “Formulario completado:” + campos (sin Translation missing).
3. El cliente no recibe mensaje de confirmación.
4. Tras el Flow, reply libre (`can_reply` / ventana 24h) sigue abierto vía el incoming.

**Estado:** ✅ Fijado 2026-07-23 en `fix/whatsapp-flow-internal-response`.

### B-NEW-13 — Pivot en paneles de reporte colapsa filas de agentes

**Severidad:** Alta (producción) — tras PR #29, tabla resumen de agentes con
`pivot.column_attribute` (p.ej. atributo tipo “venta”/producto) mostraba **una
sola fila** o perdía agentes; se esperaba cruce Excel (agentes × valores).

**Síntoma:**

1. Panel agent summary sin pivot: N agentes.
2. Al poner un CA en Columnas (pivot): quedan 1–pocos agentes; el resto
   desaparece en lugar de mostrar ceros por segmento.

**Causa raíz:**

1. `build_pivot_rows` solo emitía `buckets.keys` — dimensiones vistas al
   escanear conversaciones que además pasan el filtro de `column_values`.
2. El scan usaba `reorder(:id).limit(2000)`, sesgado a conversaciones viejas
   y truncando cuentas grandes → pocos assignees en el bucket.

Flat summary usa `AgentSummaryBuilder` (todos los `account_users`); pivot no.

**Fix aplicado:**

1. Sembrar buckets con los mismos dimension ids que el summary plano
   (`pivot_baseline_dimension_ids`).
2. Acumular con `in_batches` sin el `limit` sesgado (timeout de statement
   sigue acotando).
3. Smoke: `tmp/smoke_pivot_agent_rows.rb` — pivot/subset row count ≥ flat.

**Archivos:**

- `app/services/reports/panel_runner_service.rb`
- `tmp/smoke_pivot_agent_rows.rb`

**Migración BD:** no. Paneles guardados: sin cambio de config (transparente).

**Cómo probar:**

1. Seed demo: `tmp/seed_report_panels_demo.rb`.
2. Smoke: `rails runner tmp/smoke_pivot_agent_rows.rb` → `OK`.
3. UI: panel «Demo Agentes × Ventas» — mismas filas de agente con y sin
   Columnas=Producto; celdas 0 donde no hay cruce.

**Estado:** ✅ Fijado 2026-07-23 en `fix/report-panels-pivot-agent-rows`.

### B-NEW-19 — Pivot muestra Nombre/Puesto = 0 + KPI ≠ suma agentes

**Severidad:** Alta (producción) — con `pivot.column_attribute` la tabla
“Resumen de agentes” listaba 7 filas pero **Nombre** y **Puesto** salían `0`.
Además el KPI Conversaciones (cuenta) no coincidía con la suma de la tabla
(faltaba bucket sin asignar).

**Síntoma:**

1. Pivote por CA (p.ej. Tipo de conversación): filas de agente OK en cantidad
   (B-NEW-13) pero identidad en `0`.
2. KPI Conversaciones = 8; suma tabla agentes = 2 (solo asignadas).

**Causa raíz:**

1. `build_pivot_rows` setea `:name`/`:rank` (symbol) y luego
   `expanded_columns.each { row[col] = 0 if nil }` con strings → JSON queda `0`.
2. Tabla agrupa por `assignee_id`; `nil` no tenía fila.

**Fix aplicado:**

1. Keys string + no rellenar columnas de identidad.
2. Fila sintética `UNASSIGNED_AGENT_ID = 0` (“Sin asignar”) en plano y pivote.
3. Copy EN/ES: Conversaciones (cuenta) vs (asignadas); hints de filtro status.
4. Smoke: assert name/rank ≠ 0 + fila unassigned.

**Archivos:**

- `app/services/reports/panel_runner_service.rb`
- `tmp/smoke_pivot_agent_rows.rb`
- `config/locales/en.yml`, `es.yml`
- `app/javascript/dashboard/i18n/locale/{en,es}/report.json`

**Migración BD:** no.

**Cómo probar:**

1. Panel con pivote → Nombre/Puesto reales.
2. Plano: suma Conversaciones (agentes + Sin asignar) ≈ KPI.
3. Smoke: `rails runner tmp/smoke_pivot_agent_rows.rb`.

**Estado:** ✅ Fijado 2026-07-24 en `fix/report-panels-pivot-identity`.

### B-NEW-20 — Aggregation / flat CA measures truncaban el universo

**Severidad:** Alta (producción) — métricas `source: aggregation` y columnas
`ca:*__sum` / `__count` en summary plano no coincidían con
`conversations_count` ni con el pivot (mismo panel / rango).

**Síntoma:**

1. KPI / Count de conversaciones = N (completo vía ReportBuilder).
2. Sum(ventas) / Count(attr) mucho más bajo o sesgado a conversaciones viejas.
3. Pivot (ya full-scan) ≠ flat CA measure en el mismo rango.

**Causa raíz:**

1. Aggregation: `.limit(100)` al cargar conversaciones.
2. Flat CA: `reorder(:id).limit(2000)` — mismos IDs tempranos que B-NEW-13.
3. Date-attribute charts: `limit * 5` sobre `updated_at`.

**Fix aplicado:**

1. `each_conversation_in_batches` (mismo patrón que pivot) para aggregation,
   flat CA por dimensión/label, y rangos por CA date.
2. Contacts aggregation: `DISTINCT contact_id` sin tope artificial.
3. Detail tables: caps `DETAIL_*_LIMIT` + flag `truncated` cuando rows < total.
4. Smoke: `tmp/smoke_panel_full_scan.rb`.

**Archivos:**

- `app/services/reports/panel_runner_service.rb`
- `app/models/saved_report_panel.rb`
- `tmp/smoke_panel_full_scan.rb`
- `docs/REPORT_PANELS.md`

**Migración BD:** no (fase 1). Ver también `date_attribute` (fase 3).

**Cómo probar:**

1. Seed demo: `tmp/seed_report_panels_demo.rb`.
2. Smoke: `rails runner tmp/smoke_panel_full_scan.rb` → `ok`.
3. UI: métrica aggregation Sum(ventas) ≈ suma de `ca:ventas__sum` en summary.

**Estado:** ✅ Fijado 2026-07-24 en `fix/report-panels-correctness`.

### B-NEW-21 — Panel date_attribute + NumericParser + UX filtros

**Severidad:** Media — semántica de fechas/metadatos y parseo inconsistente
hacían que “ventas del mes” o Sum con `"1.000,50"` no cuadraran.

**Fix aplicado (mismo branch `fix/report-panels-correctness`):**

1. `date_attribute` en `saved_report_panels` (`""` = created_at, `ca:key` = CA date).
2. `CustomAttributes::NumericParser` compartido (runner + fórmulas).
3. Sum/Avg saltan no-parseables; Count = atributo presente.
4. UI: selector fecha del panel; banner filtros mixtos; “Mostrando N de M”;
   hint contact_ca lifetime.

**Smokes:** `tmp/smoke_numeric_parser.rb`, `tmp/smoke_panel_date_attribute.rb`.

**Migración:** `20260724190000_add_date_attribute_to_saved_report_panels.rb`.

**Estado:** ✅ Fijado 2026-07-24.

---

### B-NEW-200 — Crear tareas internas desde reglas y macros (A09)

Las acciones de backend ahora admiten `create_internal_task` con título, agente opcional
y vencimiento relativo. La tarea conserva el vínculo al contacto mediante su conversación,
los callbacks y la difusión privada existentes. Redis reserva la combinación origen,
conversación y título durante 24 horas con `SET NX EX`.

Archivos: `app/services/automation_rules/internal_task_parameters.rb`,
`app/services/internal_tasks/automated_create_service.rb`, `app/services/action_service.rb`,
`app/services/automation_rules/action_validation_service.rb`, `app/models/automation_rule.rb`,
`app/models/macro.rb` y `app/models/internal_task.rb`.

Autoría automática: usuario nulo y metadatos explícitos de sistema, sin atribuirla a una persona.
Requiere migración `20261023140000_allow_system_created_internal_tasks.rb` antes de habilitar la acción.
La creación manual sigue exigiendo autor; no hay cambios de frontend ni traducciones.

Cómo probar: guardar regla/macro con `[{title: 'Llamar al cliente', due_in: {duration: 2, unit: 'days'}}]`;
ejecutarla dos veces sobre la misma conversación y comprobar una sola tarea con vencimiento en dos días.
Probar agente de otra cuenta, administrador sin rol agente y duración superior a 365 días: rechazo al guardar.
Comprobar recepción del evento por asignado/administradores y ausencia para otro agente.

Specs: `spec/services/internal_tasks/automated_create_service_spec.rb`,
`spec/services/automation_rules/internal_task_parameters_spec.rb`,
`spec/services/automation_rules/action_validation_service_spec.rb`,
`spec/services/automation_rules/action_service_spec.rb`, `spec/services/macros/execution_service_spec.rb`
y `spec/models/internal_task_spec.rb`. RSpec/RuboCop pendientes de ejecución Docker por el PM.
### B-NEW-199 — Recetas por contacto: ventana WhatsApp Cloud y alcance (2026-10-23)

**Problema:** el servicio de acciones ya omitía el texto libre fuera de ventana,
pero el runner podía conservar cupo y deduplicación en acciones diferidas omitidas.
La vista previa solo exponía candidatos y le faltaba el permiso explícito en Pundit.

**Cambio:** `app/services/automations/contact_based_rule_runner.rb` omite la ejecución
con `window_closed_needs_template` cuando contiene `send_message` y la conversación
destino de WhatsApp Cloud no permite responder. Reutiliza `Conversation#can_reply?`,
libera cupo y ventana propios y registra regla/contacto. Las plantillas siguen su flujo.
`candidates_count` conserva el entero; `candidates_breakdown` agrega diagnóstico de
ventanas existentes y exclusiones por etiqueta de prueba. Los conteos de ventana
incluyen todos los candidatos con conversación Cloud, también los excluidos por prueba.

**API:** `reach_preview` conserva `count` y agrega `candidates`, `with_open_window`,
`window_closed`, `excluded_by_test_mode`; exige administrador de la cuenta vía
`AutomationRulePolicy#reach_preview?`. Crear/editar una receta con texto libre para
Cloud permite guardar y agrega `warnings: ['whatsapp_template_recommended']`.
La simulación existente solo admite eventos conversacionales, no `time_triggered`.

**Cómo probar:** specs en `spec/services/automations/contact_based_rule_runner_spec.rb`
y `spec/controllers/api/v1/accounts/automation_rules_controller_spec.rb`: límite de
24 h con reloj fijo, apertura posterior, diferidos, plantilla, canal alternativo,
dedupe previo, desglose sin crear conversaciones, permisos y aislamiento por cuenta,
advertencias aditivas en create/update. Regresión completa de ambos runners y lint
pendientes del PM en Docker según `docs/TESTING.md`. Sin migraciones ni cambios de UI.

## 3. Fijados en sesión anterior (tasks / UX)

### TASK-001 — Notas privadas en timeline

Reglas movidas a `Conversations::PrivateNoteVisibility` (misma lógica).

### TASK-002 — `clearSelectedState` en módulo internalTasks

### TASK-003 / TASK-004 — claim 409 JSON + depends_on misma cuenta

### UX-001 / UX-002 — reply preview notas + snapshot botones WA

Ver secciones 5b previas / commits en PR #3.

---

## 4. Out of scope (NO tocado)

- Kanban drag-and-drop
- Default `enable_audio_alerts`
- Patch ActionCable `staleThreshold` en `node_modules`
- Instagram OAuth POST
- panel-ai / Meta Live
- Validaciones P2: assignee/team same-account, status transitions estrictas

---

## 5. Bugs abiertos (no bloquean grupales)

| ID | Descripción | Severidad | Notas |
|----|-------------|-----------|-------|
| TASK-006 | Código muerto BotInboxMenuEditor (panel-ai) | Baja | Fuera de este repo |
| TASK-007 | Mojibake emoji en `ContactInfo.vue` | Baja | Cosmético |
| TASK-008 | Índice position | — | **Stale / cerrado** |
| P2-VALID | assignee/team_id sin check same-account; status libre en PATCH | Baja | Backlog |
| CABLE-OPS | presence / proxy idle / staleThreshold | Ops | Documentado en INTERNAL_TASKS |

---

### B-NEW-14 — Business rules, time automations, multi_list

**Feature (2026-07-23).** Guardrails in account `settings.business_rules` via
`Conversations::BusinessRulesGuard`; time automations with
`event_name: time_triggered` + `schedule` jsonb +
`Automations::TimeBasedSchedulerJob` (from `TriggerScheduledItemsJob`);
custom attribute `multi_list` (display type 9) with JSON array values and
`contains` filters.

**Migración:** `20260723210000_add_schedule_to_automation_rules.rb`

**Cómo probar:** Settings → Conversation Workflow (activate guard preset) →
status change blocked with alert; Automations → By time tab + preset;
Custom Attributes → Multi-select list → filter contains.

**i18n ES (2026-07-23):** `es/businessRules.json` + tabs/schedule en
`es/automation.json` + `MULTI_LIST` en `es/attributesMgmt.json`. UI locale ES
debe mostrar copy en español (rebuild Vite local).

**B-NEW-16 (ledger order + window_id, 2026-07-23):**
`TimeBasedRuleRunner` claimed Redis before `conditions_match?`, burning the
~90d ledger when filters failed. Order is now conditions → claim → actions.
Hours `window_id` no longer uses `last_activity_at` (label/assign churn);
it uses `time_rule_message_id` + `time_rule_message_at` from the same
`latest_messages` join as the SQL scope.

**B-NEW-17 (CRM P0 unlock on B-NEW-14/16, 2026-07-23):**
Time-triggered FE actions now include
`update_conversation_custom_attribute` /
`update_contact_custom_attribute`. Relative date CA values use Liquid via
`MessageRendererService` + `LiquidFilters::DateFilter`:
`{{ date.today }}`, `{{ date.today | plus_days: N }}`,
`{{ date.today | minus_days: N }}` (DateDrop `days_from_now`/`days_ago`
cannot take Liquid args — use the filters). `days_since_attribute` SQL
skips non-ISO strings instead of raising. Preset `seguimiento_30d` +
Index defaults `status=open` when schedule `attribute_key` is blank.

**B-NEW-18 (smoke VPS attrs → local Docker, 2026-07-24):**
Imported prod DFIT conversation CAs (`fecha_seguimiento`, `fecha_venta`, …)
into local account 1. Seed conv **#154** open with `fecha_seguimiento` ≈ 35d
ago. Upserted active time rule `Seguimiento 30d (smoke DFIT)` (id **9**):
`days_since_attribute` on `fecha_seguimiento` / 30d → `send_message` +
`update_conversation_custom_attribute` (`{{ date.today }}`) +
`notify_assignee`. `TimeBasedRuleRunner` fired: outgoing msg **#1319**,
CAs updated `2026-06-19` → `2026-07-24`, no exception. Preset defaults now
use prod keys `fecha_seguimiento` / `fecha_venta` (alias `ultimo_seguimiento`
is local-only).

### B-NEW-197 — Historial de ejecución de automatizaciones (2026-10-23)

- Archivos: `automation_rule_runs`, `AutomationRules::RunRecorder`, `AutomationRules::ActionService`,
  `Automations::ContactBasedRuleRunner`, `AutomationRules::ProcessPendingExecutionJob`, modelo y controlador de reglas.
- Cambio: una fila por ejecución con resultado por acción, clase e índice del error sin mensajes ni datos del cliente;
  omisiones de cupo/ventana/sin envío y esperas conservan sus motivos. Desactivar una regla inválida deja historial.
- Lectura: `GET /api/v1/accounts/:account_id/automation_rules/:id/runs`, solo administradores de la cuenta,
  páginas de 25, filtros por resultado y conversación. Sin pantalla en este PR.
- Retención: purga diaria a los 30 días; bloqueo por regla para limitar `executed` a partir de 1000 filas diarias
  y contador `suppressed_executed_count` en la última fila. Los errores siguen registrándose.
- Verificación: specs del recorder, ActionService, listener, runners temporal/contacto, esperas, purga, modelo y API.
  RSpec/RuboCop pendientes del PM en Docker, según el brief; revisión estática y `git diff --check` realizadas.
- Deploy: requiere migración `20261023120000_create_automation_rule_runs.rb` y reiniciar Rails/Sidekiq.


### B-NEW-15 — Flows menu no visible (local / prod) — secundario

**Estado:** ✅ portado (2026-07-24) sobre `feat/business-rules-time-multilist`.
Traído desde `feat/conversation-flows`: modelos `Flow`/`FlowRun`/`FlowEvent`,
API, store/rutas FE, Sidebar **Flows**, flag `flows_v1`, acción automation
`enter_flow`. Business-rules UI/servicios intactos. Activar por cuenta:
`Account.find(1).enable_features!('flows_v1')`. UI: rebuild Vite/Docker assets
si el menú no aparece tras restart Rails.

### B-NEW-198 — Automatizaciones al cambiar atributos del contacto (2026-10-23)

- Archivos: `app/listeners/automation_rule_listener.rb`, `app/models/{contact,automation_rule}.rb`
  y `app/services/automation_rules/{contact_updated_service,condition_validation_service}.rb`.
- Cambio: `contact_updated` usa el catálogo compartido y evalúa condiciones sobre la conversación abierta o pendiente
  más reciente; las condiciones `inbox_id/equal_to` restringen el destino antes de elegirlo. No crea conversaciones.
- Seguridad: el evento conserva `Current.executed_by` para ignorar cambios causados por automatizaciones;
  Redis reclama una vez por regla/contacto/hash durante diez minutos. Límite propio de 200 ejecuciones por cuenta
  y día (`Time.zone.today`), porque las importaciones no tienen un indicador común en `Current`.
- Alcance: atributos personalizados y estándares filtrables; diferencias JSON desglosadas para `attribute_changed`.
  Etiquetas del contacto pendientes: no existe una notificación específica con su diferencia; `labels` conserva
  el significado actual de etiquetas de conversación. No admite espera ni simulación para este evento.
- Verificación: `spec/services/automation_rules/contact_updated_service_spec.rb` cubre A1–A8, TTL, cupo, orden
  y actor; el spec del controlador comprueba que simularlo devuelve 422. Revisión estática y `git diff --check`;
  RSpec/RuboCop pendientes del PM en Docker, según `.codex/BRIEF-CONTACTO.md`. Sin frontend ni migraciones.

### B-NEW-22 — Flows: columna infinita + nota handoff con IDs técnicos

**Síntoma:** el editor listaba todos los pasos en una columna; con muchas ramas
era confuso. La nota privada de handoff volcaba IDs
(`handoff_n1784…_boton3`) en lugar del camino del cliente.

**Fix (2026-07-24):**
1. `Flows::HandoffService` — resumen legible: motivo + camino con preview de
   mensaje y botón elegido (trail `matched` + `buttons[].title`).
2. `buildGraph` — `HANDOFF_REASON` usa el **title** del botón.
3. Editor canvas: `FlowCanvas.vue` (`@vue-flow/core` + dagre TB), acciones en
   `FlowProperties.vue`. Contrato `buildGraph`/`nodeToStep` intacto.

**Archivos:** `handoff_service.rb`, `Edit.vue`, `FlowCanvas.vue`,
`FlowStepNode.vue`, `FlowTerminalNode.vue`, `FlowProperties.vue`,
`en.yml` (`flows.handoff_note.*`), `en/flows.json`.

**Cómo probar:**
1. Settings → Flows → editar: canvas con edges por botón; click → panel derecho.
2. Flujo con handoff → nota privada sin IDs; camino tipo
   `"¿Qué necesitas?" → chose "Botón 3"`.
3. Rebuild Vite/Docker assets para ver el canvas.

### B-NEW-23 — Flows editor polish (layout / botones / perf)

**Síntoma:** panel derecho mezclaba meta del flow + exit + paso; 3 slots de
botones siempre visibles; canvas lento por fitView/re-layout al tipear.

**Fix (2026-07-24):**
1. Layout full-bleed: canvas + `FlowStepInspector` derecha + `FlowFooter` abajo
   (exit policy colapsable).
2. Toggle Wait for reply + add/remove botones (máx. 3); default off.
3. Nombre de nodo (`data.title`) editable en canvas/inspector.
4. Handles por botón + flechas; fitView solo al cargar/add/remove step;
   debounce content sync; sin MiniMap.

**Cómo probar:** Settings → Flows → editar: canvas amplio, footer con Save,
toggle botones, renombrar nodo, conectar desde handle de botón.

### B-NEW-24 — Flows: Activo/categoría/exit drawer/inspector

**Síntoma:** Activo en el editor; exit policy comía el canvas; delay duplicado;
toolbar del mensaje se desbordaba; sin categoría.

**Fix (2026-07-24):**
1. Switch Activo en la lista (`FlowsTableRow`); quitado del header.
2. Columna `flows.category` + input en header + columna en lista.
3. Exit rules vía Dialog drawer desde el header (canvas `min-h-[50vh]`).
4. Inspector: sin delay duplicado; secciones Actions/Buttons; overflow en editor.
5. Nodos TB más compactos con chips de botón visibles.

**Cómo probar:** lista toggle activo; editar categoría; Exit rules no tapa canvas;
configurar botones sin scroll infinito de delay doble.

### B-NEW-206 — Captain: persistencia confirmada y borrado seguro (2026-10-24)

- Archivos: `components-next/captain/assistant/{AddNewRulesDialog,AddNewRulesInput,AddNewScenariosDialog,RuleCard,ScenariosCard}.vue`, páginas de pautas, límites y escenarios, wrappers de borrado de Captain y Campañas, `dialog/Dialog.vue` y `reports/panels/Edit.vue`.
- Causa: altas y ediciones limpiaban o cerraban el diálogo antes de saber si el servidor había guardado; un 422 o un fallo de red hacía perder el borrador. «Agregar todos» ocultaba las sugerencias sin esperar el guardado y el borrado no pedía confirmación en todos los puntos.
- Arreglo: altas y ediciones esperan el resultado; solo el éxito limpia o cierra y el fallo conserva el borrador. Mientras hay una petición pendiente se bloquean los envíos repetidos. El borrado individual y por lote pide confirmación y los errores conservan el contexto. Escenarios usa `allSettled`, informa cuántos se borraron y reintenta solo los fallidos. Pautas y límites guardan su lista en una sola petición.
- Cómo probar: provocar un 422 o un corte de red al crear o editar y reintentar; cancelar un borrado (no debe enviar nada); confirmar dos veces durante la espera; en un lote, rechazar un solo ID y comprobar que el reintento no vuelve a borrar los que ya se borraron.
- Specs: `assistant/Persistence.spec.js`, `assistants/Persistence.spec.js`, `pageComponents/DeletePersistence.spec.js`, `dialog/Dialog.spec.js` y `panels/specs/Edit.spec.js`. Sin backend ni migraciones. Los textos nuevos de borrado quedan en inglés hasta sincronizar con Crowdin.

### B-NEW-25 — Flows: acciones montadas + dropdown roto en inspector

**Síntoma:** Acciones del paso se veían apiladas sin número/borde; al abrir el
select aparecía un input de búsqueda suelto con el trash (dropdown clipado por
`overflow-hidden` del wrapper).

**Fix (2026-07-24):**
1. Cada acción en card con label `Action {n}` + trash en header (como botones).
2. Quitado `overflow-hidden` del wrapper de acciones; dropdowns visibles.
3. `dropdown-max-height` acotado en el inspector estrecho.

**Cómo probar:** editar paso con varias acciones → cards numeradas; abrir
“Add label” / tipo de acción → menú usable, sin fila de búsqueda fantasma.

### B-NEW-26 — Flows: acciones horiz., tipos únicos, panel izq, i18n

**Síntoma:** acciones apiladas vertical; tipo repetible; menubar de texto oculto;
dropdown limitado a ~3 opciones; header desalineado; strings EN en UI ES;
inspector a la derecha.

**Fix (2026-07-24):**
1. Acciones horizontales (como Automatizaciones) + menubar ProseMirror visible.
2. Tipo de acción único por paso (filtro en select + add deshabilitado).
3. `dropdown-max-height: max-h-80`; panel config a la izquierda / canvas a la derecha.
4. Header botones alineados con `items-end`; `es/flows.json` sincronizado.

**Cómo probar:** layout L/R; añadir 2× “Add label” bloqueado; menú con muchas
opciones; editor de mensaje con toolbar; textos ES en header/inspector.

### B-NEW-28 — Login 500 post-merge 4.16.1 (`feature_api_and_webhooks?`)

**Severidad:** P0 prod — `/auth/validate_token` 500; dashboard no entra.

**Causa:** merge upstream con `-X ours` en `config/features.yml` omitió los
flags de `feature_flags_ext_1` (incl. `api_and_webhooks`).

**Fix:** append flags ext_1 (orden upstream) + jbuilder usa
`api_and_webhooks_enabled?` + `Message.unscoped` en time-based DISTINCT ON.

**Deploy:** merge a `develop` + GHCR redeploy. Sin migración.

### B-NEW-29 — Dashboard JS roto post-4.16.1 (`hasFilteredUnreadCounts` / `useI18n`)

**Severidad:** P0 prod — login OK pero sidebar/commandbar crash; UI incompleta.

**Causa:** merge `-X ours` dejó usos de `hasFilteredUnreadCounts` / `hasDataImport`
sin definir, y `useAgentsList.js` sin imports de `vue` / `vue-i18n`.

**Fix:** definir computeds + `UNREAD_COUNT_FOR_FILTERS` en featureFlags + imports.

**Deploy:** merge PR + GHCR rebuild (assets en imagen).

### B-NEW-207 — Búsqueda y encabezados disponibles en móvil (2026-10-24)

- Archivos: `settings/components/BaseSettingsHeader.vue`, `components-next/Campaigns/CampaignLayout.vue`, `settings/reports/components/ReportHeader.vue` y `settings/agents/Index.vue` bajo `app/javascript/dashboard/`.
- Causa: la búsqueda estaba oculta bajo `sm`, los grupos de botones no se envolvían, el botón de campañas tenía altura fija y texto truncado, y las acciones de cada fila de Agentes se salían de la pantalla.
- Arreglo: búsqueda visible con nombre accesible, grupos que se envuelven, títulos y acciones en varias líneas, y la fila de Agentes con el correo y el rol envueltos y los botones siempre dentro de la pantalla. Los estilos del encabezado de informes solo alcanzan al botón directo, no al menú de descarga. Se conservan modelos, slots, permisos y eventos.
- Verificación: specs de `BaseSettingsHeader`, `CampaignLayout` y `ReportHeader`; páginas reales de Agentes, Macros, Etiquetas, Campañas e Informes a 390 y 1280 px en claro y oscuro. Sin backend ni migraciones.

### B-NEW-30 — `toggle_status` 500 (resolve / reopen / pending / snooze)

**Severidad:** P0 prod — cualquier cambio de estado vía
`POST .../conversations/:id/toggle_status` devolvía 500
(account 2 / conv 929 en `inbox.paluhub.com`).

**Causa:** `status_change_activity` pasaba `content_attributes:` a
`activity_message_params`, pero el helper solo aceptaba `content` →
`ArgumentError` en Ruby 3 dentro de `after_update_commit`. No es business
rules (esas serían 422).

**Fix:**
- `ActivityMessageHandler#activity_message_params(content, content_attributes: nil)`
  mergea `content_attributes` cuando está presente.
- Modal resolve: inputs `currency` / `percent`; pickers excluyen CAs con
  `formula`.
- `BusinessRulesGuard`: `config` no-Hash → `{}` (evita 500 con settings corruptos).

**Archivos:**
- `app/models/concerns/activity_message_handler.rb`
- `app/services/conversations/business_rules_guard.rb`
- `ConversationResolveAttributesModal.vue`, `constants.js`
- `useConversationRequiredAttributes.js`, `ConversationRequiredAttributes.vue`,
  `BusinessRuleForm.vue`

**Cómo probar:** resolve → reopen → pending → snooze sin 500; activity
message en timeline; si hay required `currency`/`percent`, modal los
edita. Local: `.\scripts\dev-up.ps1` (Vue en imagen). Prod: merge
`develop` + GHCR redeploy (sin migración).

### B-NEW-31 — Business rules: contact attrs + zero-as-blank + TYPE_HELP

**Feature.** Guardrails pueden exigir atributos de **conversación y contacto**.
En `number`/`currency`/`percent`, el valor `0` cuenta como vacío. El form
muestra `TYPE_HELP` por tipo de regla. Al resolver, el modal pide ambos
modelos y guarda contacto vía `contacts/update` antes de `toggle_status`.

**Archivos:**
- `Conversations::BusinessRulesGuard`
- `BusinessRuleForm.vue`, `useConversationRequiredAttributes.js`
- `ConversationResolveAttributesModal.vue`, `ResolveAction.vue`
- `en/es/businessRules.json`

**Cómo probar:** Settings → Business rules → exigir CA de contacto +
condicional `tipo=venta` → currency; resolve con `0` bloquea; valor > 0 OK.
Local: `up -d --build` (Vue en imagen).

### B-NEW-202 — Automatizaciones: condición de origen de campaña

- **Fecha:** 2026-10-23. Backend; sin migración ni frontend.
- **Archivos:** `app/models/automation_rule.rb`, `app/services/automation_rules/condition_validation_service.rb`.
- **Cambio:** habilitar `campaign_id` en eventos de conversación, mensaje y reglas por tiempo, reutilizando el catálogo y el evaluador
  existentes. Operadores: `equal_to`, `not_equal_to`, `is_present`, `is_not_present`. Igualdad exige `values: [id]` (un entero positivo,
  ID interno de una campaña de la misma cuenta); presencia admite omitir `values`, `null` o `[]`. IDs ajenos/inexistentes devuelven
  un error que identifica `campaign_id`. La API conserva su respuesta 422. No modifica filtros de conversaciones ni segmentos.
- **Límites:** `not_equal_to` conserva SQL `NOT IN`: no coincide con `NULL`. WhatsApp solo atribuye por contexto explícito de respuesta
  de Meta, sin reemplazar una campaña previa; no atribuye texto libre. Esta condición lee la conversación y no acredita cada mensaje.
- **Cómo probar:** crear una regla por campaña y comparar conversación de esa campaña, de otra y sin campaña; probar los cuatro
  operadores, guardado de IDs ajenos/eliminados, simulación, listeners y ambos runners por tiempo. Specs añadidos/ampliados en
  `spec/services/automation_rules/`, `spec/listeners/automation_rule_listener_spec.rb`, `spec/services/automations/`,
  `spec/services/business_rules/conditions_matcher_spec.rb` y `spec/controllers/api/v1/accounts/automation_rules_controller_spec.rb`.
  RSpec/RuboCop pendientes de ejecución del PM en Docker según `docs/TESTING.md`.

### B-NEW-32 — Business rules UX: ConditionRow + categorías + multi-status

**Feature.** Guards usan `conditions[]` (mismos filtros que Automations via
`ConditionRow`), pueden exigir attrs por **categoría**, y el pre-check FE
cubre resolve/pending/open (forbid/assignee/nota vía alert). Las reglas por
tiempo siguen solo en **Automations** (`time_triggered`), no en Business rules.

**Archivos:**
- `BusinessRules::ConditionsMatcher`, `RequiredAttributeKeys`, Guard
- `BusinessRuleForm.vue`, `AttributeRequirementPicker.vue`, Index
- `useBusinessRulesStatusGuard.js`, ResolveAction / ChatList / bulk

**Cómo probar:** form Cuando/Entonces; categoría Venta exige keys nuevas;
resolve modal; pending con require_reason. Local: `--build`.

### B-NEW-211 — Rangos de fecha utilizables en el teléfono (2026-10-24)

- Archivos: `components/ui/DatePicker/DatePicker.vue` y sus componentes de calendario, bajo `app/javascript/dashboard/`.
- Causa: panel fijo de 880 px con dos calendarios, que quedaba fuera de la pantalla en móvil.
- Arreglo: bajo `lg` el selector se muestra como diálogo con un calendario, atajos plegables, borrador con Aplicar y Cancelar y controles de 44 px. Escritorio conserva dos calendarios, no cambia el cálculo de fechas ni los datos que reciben los seis consumidores. Pulsar el disparador abierto en escritorio vuelve a aplicar el borrador, y las etiquetas accesibles de los días usan el idioma de la aplicación.
- Verificación: `DatePicker/specs/{DatePicker,DatePickerConsumers,DatePickerResponsive}.spec.js` y `CalendarWeek.spec.js`, más las suites de informes y auditoría en UTC y America/Guayaquil. Capturas reales a 390 y 1280 px, antes y después. Sin backend, migraciones ni claves de traducción nuevas.

### B-NEW-33 — Dialog Business rules: clic en filtro guardaba la regla

**Causa:** `Dialog` usa `<form @submit>` y `MultiSelect` / trash / “Añadir
condición” renderizaban `<button>` sin `type="button"` → submit al abrir
estados (multiSelect).

**Fix:** `type="button"` en `MultiSelect.vue`, `ConditionRow.vue`,
`BusinessRuleForm.vue`.

**Cómo probar:** editar regla → condición Status → abrir valores; el modal
no debe cerrarse ni guardar.

### B-NEW-34 — Motivo al posponer: FE bloqueaba nota y snooze sin error

**Causa:** pre-check FE marcaba `needsPrivateNote` sin mirar mensajes →
pending nunca llegaba al Guard. Snooze vía cmdbar no formateaba 422 de BR.

**Fix:** defer nota privada al API; snooze pre-check + `formatBusinessRuleError`;
si falta CA de motivo al posponer desde ResolveAction, modal → luego picker.

**Cómo probar:** preset motivo (solo nota) → pending sin nota → alert API;
añadir nota privada → pending OK. Snooze sin nota → alert legible.

### B-NEW-35 — Automation por tiempo + regla “motivo al posponer” chocaban

**Causa:** `BusinessRulesGuard` corre en todo `will_save_change_to_status?`.
Una automation (`snooze_conversation` / `pending`) no llena motivo/nota →
`RecordInvalid` tragado por `AutomationRules::ActionService` → mensaje sí,
posponer no.

**Fix:** si `Current.executed_by` es `AutomationRule`, el Guard retorna OK
(candados para agentes; robots no). Macros / UI agent siguen validados.

**Archivo:** `app/services/conversations/business_rules_guard.rb`

**Cómo probar:** regla motivo en snoozed + automation “tras N min → snooze +
mensaje” → conversación queda snoozed y mensaje enviado. Agente snooze
sin motivo → sigue bloqueado.

### B-NEW-36 — Exigir agente + dropdown contacto transparente

**Causa (assignee):** FE trataba `meta.assignee` (incluye bot del canal) como
válido → la regla nunca pedía humano. Backend ya miraba `assignee_id` (User).

**Fix:** FE usa `isHumanAssigneeMeta` o team; copy aclara “humano / bot no cuenta”.

**Causa (UI):** `animate-pulse` en Sin asignar anima opacity → stacking context
+ menú `bg-n-alpha` → Acciones de conversación se ven a través del dropdown.

**Fix:** quitar pulse; menú con fondo sólido + `z-50` al abrir en
`OutlinedSelectField`.

**Archivos:** `useBusinessRulesStatusGuard.js`, `ContactAssigneeSelector.vue`,
`OutlinedSelectField.vue`, i18n businessRules.

**Cómo probar:** inbox con bot, conversación solo-bot, regla exigir al abrir →
bloquea hasta asignar humano/equipo. Contacto sin agente → abrir selector →
lista legible opaca.

### B-NEW-209 — Panel activo de tareas a ancho completo en el teléfono (2026-10-24)

- Archivos: `routes/dashboard/tasks/TaskView.vue` y `components-next/InternalTasks/{TaskList,TaskKanban,TaskDetail,TaskDetailHeader,TaskListTeamFilter,TaskListStatusFilter}.vue`, bajo `app/javascript/dashboard/`.
- Causa: la lista fija de 340 px quedaba junto al detalle o el tablero en el teléfono, dejando la tarea fuera del área visible. Además, los menús de equipo y agente del panel de reasignar se montaban en `body`, y el cierre por clic exterior desmontaba el panel antes de guardar.
- Arreglo: bajo 768 px se alternan lista y tablero y al elegir una tarea solo se muestra el detalle con botón de retorno; los filtros se conservan. Los menús del panel de reasignar se montan dentro del propio panel. El tablero solo consulta al servidor cuando es visible y pospone la actualización mientras está oculto. Escritorio conserva sus paneles.
- Verificación: `tasks/specs/TaskView.spec.js`, `InternalTasks/specs/TaskDetail.spec.js` y `TaskDetailHeader.spec.js`; capturas reales a 390 y 1280 px en ambos temas, con toques reales en el selector de reasignar. Sin backend, permisos ni migraciones.

### B-NEW-37 — Post-compra: atributo de fecha era texto libre

**Causa:** `days_since_attribute` usaba `<input>` para `schedule.attribute_key`.

**Fix:** select con CAs de conversación tipo `date` y `datetime` (display name).
Claves huérfanas de reglas viejas siguen visibles. Datetime ya castea por
día calendario (`LEFT(..., 10)::date` en el runner).

**Archivos:** `AutomationRuleForm.vue`, i18n automation EN/ES,
`time_based_rule_runner.rb` (comentario).

**Cómo probar:** Automations → time triggered / preset post-compra →
dropdown lista fechas; datetime marcado; sin CAs de fecha → mensaje vacío.

### B-NEW-213 — Listas de agentes en tarjeta responsiva (2026-10-24)

- Archivos: `components-next/ListCard/{ListCard,InfoChip}.vue`, `components-next/CardLayout.vue` (nueva opción `padding`) y `settings/agents/Index.vue`, bajo `app/javascript/dashboard/`.
- Causa: la lista de Agentes era una tabla armada a mano que se salía de la pantalla en el teléfono, con separadores «|» entre correo, rol y estado y dos botones por fila.
- Arreglo: `ListCard` es tarjeta en móvil y fila compacta desde `md`, con avatar y punto de disponibilidad, subtítulo, chips de rol y verificación alineados en una columna fija a la derecha, y un menú ⋮ de 44 px con Editar y Eliminar que respeta los permisos y los diálogos existentes. El menú se abre hacia abajo y solo se voltea si no cabe. `CardLayout` admite `padding="compact"` sin cambiar a sus consumidores actuales.
- Verificación: specs de `ListCard`, `InfoChip`, `CardLayout`, `dropdown-menu` y `settings/agents` en UTC y America/Guayaquil. Capturas reales a 390, 768 y 1280 px en claro y oscuro. Sin backend ni migraciones.

### B-NEW-38 — Automation: nota privada de auditoría al ejecutarse

**Estado:** sustituido por **B-NEW-44** (2026-07-28). Ya no se deja nota audit al
final de cada run; ver B-NEW-44.

**Causa original:** time/event rules podían correr sin rastro visible.

**Fix original (2026-07-27):** nota privada vía `Conversations::SystemAuditNote`.

### B-NEW-203 — Captain espera los mensajes de una ráfaga antes de responder

- **Cambio:** `reply_delay_seconds` en `Captain::Assistant.config`, entero de 0 a 30;
  6 segundos cuando falta y 0 sin espera adicional. Sin migración ni frontend.
- **Archivos:** `enterprise/app/models/captain/assistant.rb`,
  `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`,
  `enterprise/app/services/captain/conversation/response_scheduler_service.rb`,
  `enterprise/app/jobs/captain/conversation/response_builder_job.rb`.
- **Comportamiento:** espera máxima entre el ajuste y los adjuntos; V1 y V2 reciben
  el ID del mensaje y descartan jobs antiguos antes de generar. Se conservan los
  descartes de V2 durante la generación y las comprobaciones de estado/asignación.
- **Cómo probar:** enviar tres mensajes en menos de 6 segundos: una respuesta al
  último, un consumo. Cambiar el ajuste por API a 0 y 10; rechazar -1, 31, texto,
  decimales y estructuras con 422. Revisar adjuntos y toma de control humana.
- **Specs:** scheduler, response builder job, assistant, assistants controller,
  hook execution y Captain unavailable bajo `spec/enterprise/`. RSpec/RuboCop
  pendientes de ejecutar por el PM en Docker con base de test aislada.
- **Límites:** no se garantiza respuesta en 60 segundos si siguen llegando mensajes
  indefinidamente. V1 solo añade descarte antes de generar; no durante generación.

### B-NEW-44 — Automation: nota audit ruidosa → tuerca + actividades

**Síntoma:** cada automatización dejaba nota privada *«Automatización "X" ejecutada»*
(B-NEW-38) además de mensajes/activities ya existentes.

**Fix (2026-07-28):**
1. Quitar `append_system_audit_note` al final de `ActionService#perform`.
2. Outbound: `automation_rule_id` + `automation_rule_name` en `content_attributes`;
   icono tuerca en `MessageMeta.vue` con tooltip (**camelCase** — `MessageList` convierte keys).
3. Acciones no-mensaje: activity con texto *«por automatización «nombre»»* vía
   `automation.activity_actor` + tuerca en `Activity.vue`; attrs de regla en activity messages.
4. Mantener `SystemAuditNote` solo para ventana WA/Meta cerrada
   (`messaging_window_skipped`).
5. `MessageBuilder`: ya no pisa `content_attributes` con merge de solo `automation_rule_id`.

**Follow-up (2026-07-28):** tuerca invisible — assets Vite en imagen Docker sin rebuild;
`MessageMeta` leía snake_case pero el store usa camelCase. **Fix v2:** `message_source`
unificado (`automation`/`macro`/`flow`) + `MessageSourceIndicator` con iconos del sidebar
(`repeat` / `toy-brick` / `git-branch`). Flujos: `flow_already_entered?` bloquea reentrada
al mismo flujo en la misma conversación. Macros: `Current.executed_by = macro` para que
activities (assign/team/labels/…) lleven icono toy-brick sin nota audit genérica.

**Archivos:** `action_service.rb`, `automation_rules/action_service.rb`,
`deferred_outbound_job.rb`, `message_builder.rb`, `lib/automation_rule_actor.rb`,
activity handlers, `MessageMeta.vue`, `en`/`es` automation.json, `docs/BUGS.md`.

**Cómo probar:** automation con `send_message` → tuerca en bubble, sin nota audit;
`assign_agent` → activity *by «Nombre regla»*; WA fuera de ventana → nota skip sí,
sin audit genérico extra.

### B-NEW-45 — Resolve crash: `.map is not a function` en business rules

**Síntoma:** al clic en Resolver →
`TypeError: (n || []).map is not a function` en
`useBusinessRulesStatusGuard.js` (`conditionValueMatches`).

**Causa:** `ConditionRow` guarda `values` como scalar (SingleSelect/Input) o
array (MultiSelect). `(expectedValues || []).map` falla si `values` es string.

**Fix:** helper `asArray` en el guard FE + `useConversationRequiredAttributes`.

**Archivos:** `useBusinessRulesStatusGuard.js`,
`useConversationRequiredAttributes.js`.

**Cómo probar:** conversación con business rules con condiciones → Resolver
sin error en consola. Hard refresh tras redeploy (assets Vite).

### B-NEW-214 — Altas y selectores Captain adaptables (2026-10-24)

- Archivos: `components-next/captain/assistant/{AddNewScenariosDialog,AddNewRulesDialog,ToolsDropdown}.vue`, `captain/{PageLayout,pageComponents/switcher/AssistantSwitcher}.vue`, `HelpCenter/{HelpCenterLayout,PortalSwitcher/PortalSwitcher}.vue` y `components/widgets/{conversation/TagTools,WootWriter/Editor}.vue`, bajo `app/javascript/dashboard/`.
- Causa: los paneles de ancho fijo y los menús extensos impedían alcanzar campos, herramientas y acciones en el teléfono.
- Arreglo: altas con Dialog y cuerpo desplazable, acciones fuera del desplazamiento y campos con etiqueta; selectores con MenuPopover, búsqueda y acción de creación. Las herramientas se muestran dentro del diálogo nativo; Escape cierra primero el menú y conserva el editor. Se mantienen rutas, identificadores, idioma del portal y confirmación de persistencia.
- Verificación: `assistant/{AddDialogs,Persistence,ToolsDropdown}.spec.js`, `switcher/AssistantSwitcher.spec.js` y `WootWriter/CaptainTools.spec.js`; abrir las altas a 390 y 1280 px, provocar un error y reintentar sin perder texto, recorrer las herramientas con flechas y Escape y crear desde una búsqueda sin resultados. Sin backend ni migraciones.

### B-NEW-46 — Modal resolve: cadena de reglas en el mismo paso

**Síntoma:** al Resolver, el modal pide `tipo_de_conversacion`; el agente elige
`Venta` y la conversación se cierra sin pedir campos de la 2ª regla. Solo al
reabrir y resolver de nuevo aparecen Y/Z.

**Causa:** el guard FE evaluaba attrs una sola vez al abrir el modal (tipo aún
vacío → 2ª regla no aplica). Además `ConditionRow` guarda `values` como
`{id,name}` y `String(objeto)` no matcheaba.

**Fix:**
1. Modal re-evalúa con el **set completo** de campos requeridos del draft
   (`requiredAttributes`), no solo los vacíos — así `tipo=Venta` no desaparece
   del form y no oscila la cadena.
2. FE/BE coercen `{id,name}` → string al comparar condiciones.
3. UX modal: fecha→hoy, datetime→ahora, lista de 1 opción auto, checkbox
   false, secciones conversación/contacto, botón Hoy/Ahora, copy de cadena.
4. `if_attribute_then_require` aplica si conditions **o** `when_*` coinciden.

**Archivos:** `ConversationResolveAttributesModal.vue`,
`ResolveAction.vue`, `ChatList.vue`, `useBusinessRulesStatusGuard.js`,
`useConversationRequiredAttributes.js`, `conditions_matcher.rb`,
`en`/`es` settings.json.

**Cómo probar:** chat con label de test + reglas tipo→venta. Resolver → elegir
Venta en el modal → deben aparecer campos de venta **sin** cerrar. Completar y
resolver en un solo flujo. Hard refresh tras redeploy.

### B-NEW-204 — Captain entiende el cambio de elección en botones de WhatsApp

**Problema:** un segundo toque sobre los botones del mismo mensaje llegaba a Captain sin contexto del cambio de elección.

**Fix:** la entrada de WhatsApp marca `button_choice_changed` y `previous_button_choice` cuando existe una respuesta entrante
anterior al mismo `in_reply_to`; toma la más reciente por `created_at` e `id`. Aplica a `button`, `button_reply` y `list_reply`,
sin inferir el mensaje padre cuando falta contexto. El formateador compartido de Captain V1/V2 añade una anotación traducida,
conservando el contenido original y el flujo normal de respuesta. `Calendar::TemplateButtonReply` conserva su deduplicación.

**Archivos:** `app/services/whatsapp/incoming_message_base_service.rb`,
`enterprise/app/services/captain/open_ai_message_builder_service.rb`, `config/locales/en.yml`, `config/locales/es.yml`.

**Cómo probar:** tocar dos opciones distintas del mismo mensaje en WhatsApp: Captain debe entender la última como un cambio.
Un tercer toque debe referir a la segunda opción. Probar también listas, mensajes padre distintos, texto libre y falta de contexto.
En citas, confirmar y luego reagendar; repetir el webhook no debe duplicar actividades.

**Specs:** `spec/services/whatsapp/incoming_message_button_choice_spec.rb`,
`spec/enterprise/services/captain/conversation/message_history_builder_service_spec.rb`,
`spec/enterprise/services/captain/open_ai_message_builder_service_spec.rb`,
`spec/services/whatsapp/incoming_message_whatsapp_cloud_service_appointment_buttons_perform_spec.rb`,
`spec/services/calendar/template_button_reply_spec.rb`.
Pendiente ejecución de RSpec y RuboCop por el PM en Docker, según el brief. Sin migraciones ni cambios de frontend.

### B-NEW-47 — Modal resolve: precarga valores + obligatorio visible

**Síntoma:** al Resolver con 4/5 attrs ya llenos, el form abría “en blanco”
(sin valores previos), sin `*` de obligatorio, y el faltante no se marcaba en
rojo hasta interactuar.

**Causa:** callers pasaban solo `missingAttributes`; al expandir a
`requiredAttributes` los campos ya llenos se hidrataban con defaults en vez de
`custom_attributes`. Además `$reset()` al abrir limpiaba errores.

**Fix:**
1. Abrir con `requiredAttributes` (fallback missing).
2. Hidratar desde conversación/contacto; blanks quedan vacíos (no default
   engañoso) y se `$touch` al abrir → rojo + scroll al primero.
3. Asterisco `*` en labels del modal.
4. Al encadenar campos nuevos: seed conversación, si no hay → smart default.

**Archivos:** `ConversationResolveAttributesModal.vue`, `ResolveAction.vue`,
`ChatList.vue`, `docs/BUGS.md`.

**Cómo probar:** conversación con venta casi completa, borrar un campo (o
dejar uno vacío) → Resolver → form muestra los valores existentes, `*` en
labels, el vacío en rojo.

### B-NEW-48 — Contact search: doble encode + campos limitados

**Síntoma:** buscar contactos con espacios, tildes o `+` no encontraba;
identifier/document case-sensitive; company no entraba en search.

**Causa:** `ContactsIndex` hacía `encodeURIComponent` y `buildContactParams`
volvía a encodear (`%20` → `%2520`). Backend usaba `LIKE` en identifier/
document_number y no buscaba company.

**Fix:**
1. Pasar `search` crudo desde `ContactsIndex` (encode solo en API).
2. `ILIKE` en identifier y document_number.
3. Incluir `additional_attributes->>'company_name' ILIKE`.

**Archivos:** `ContactsIndex.vue`, `contacts_controller.rb`, `docs/BUGS.md`.

**Cómo probar:** buscar nombre con espacio/tilde, cédula en mayúsculas/minúsculas,
y company_name → deben aparecer resultados.

### B-NEW-215 — Captain: listas, enlaces y conflictos de edición (2026-10-24)

- Archivos: controladores Enterprise Captain `assistants_controller.rb` y `documents_controller.rb`, `playground/configuration.rb`, páginas de pautas y límites, `usePlaygroundSession.js` y formulario y diálogo de documentos.
- Causa: se aceptaban listas y enlaces inválidos, dos editores podían sobrescribir cambios ajenos y los errores del servidor no siempre se conservaban en el formulario.
- Arreglo: las listas deben contener textos no vacíos; al reemplazarlas se compara el original enviado en `expected_response_guidelines` o `expected_guardrails` dentro del bloqueo del asistente. Una edición desactualizada recibe 409 sin escrituras parciales. Los clientes de ajustes y playground envían el original exacto. El formulario y el servidor validan enlaces HTTP(S); PDF y Markdown conservan su flujo. Los errores mantienen el diálogo, borrador y lista original. Sin migraciones ni cambios de permisos.
- Verificación: specs de los controladores Enterprise de asistentes y documentos, configuración de playground, `assistants/Persistence.spec.js`, `assistant/usePlaygroundSession.spec.js` y `document/DocumentForm.spec.js`. Enviar un objeto como lista devuelve 422; guardar desde dos sesiones devuelve 409 en la segunda y conserva la primera. Corregir una URL inválida y reintentar un error de duplicado conserva el formulario abierto.

### B-NEW-51 — `contacts.chat_bot` + bot vs assignee pasivo (inbox Dueño del contacto)

**Síntoma:** con auto-assign “Dueño del contacto”, el 1.er mensaje lo contesta el
bot y el 2.º queda en silencio porque Panel veía `has_human_agent`.

**Fix (Chatwoot + Panel, local):**
- Columna `contacts.chat_bot` default `true` + API + toggle UI (ficha contacto).
- Panel: gate `chat_bot` primero; reclaim AgentBot (`force`) mientras atiende;
  no callar por assignee humano pasivo; typing/visto post-buffer.
- Handoff: dueño del contacto siempre si existe; destination = solo sin dueño.
- `TypingIndicatorJob` usa `MarkReadTypingService(force: true)`.

**Archivos CW:** migración `20260729200000`, `contact.rb`, `_contact.json.jbuilder`,
`contacts_controller.rb`, `ContactChatBotToggle.vue`, `ContactInfo.vue`,
`typing_indicator_job.rb`.

**Archivos Panel:** `assignment.py`, `router.py`, `chatwoot_inbound.py`,
`handoff_policy.py`, `human_handoff.py`, `handoff-destination-picker.tsx`.

**Cómo probar (local):** inbox con Dueño del contacto + contacto con agente +
`chat_bot` ON → msgs 1–2 bot OK y assignee conversación ≈ AgentBot; handoff →
dueño; `chat_bot` OFF → silencio. Requiere migrate `chat_bot`.

### B-NEW-52 — Time automations: antes / el mismo día / después

**Problema:** `days_since_attribute` solo disparaba N≥1 días **después** de un
atributo de fecha (`fecha <= hoy − N`). No había “el mismo día” ni “N días
antes” (recordatorio de cita).

**Fix:** `schedule.relative_to` = `after` (default, igual que antes) | `on` |
`before`. Sin migración. `on`/`before` matchean el día calendario exacto;
`after` sigue con `<=` + ledger una vez.

**Archivos:** `time_based_rule_runner.rb`, `automation_rule.rb`,
`AutomationRuleForm.vue`, `validations.js`, `en/es/automation.json`.

**Cómo probar:** Automations → By time → atributo de fecha. After N=1 + fecha
ayer → dispara; On + fecha hoy → dispara; Before N=3 + fecha hoy+3 → dispara.
Reglas viejas sin `relative_to` siguen siendo after.

### B-NEW-50 — Business rules safety: lint + dry-run + kill switch

**Problema:** reglas mal configuradas (AND imposible, categorías vacías, keys
muertas) se activaban y hacían parecer “roto” Resolve.

**Fix (MVP, sin árbol primary/secondary):**
- `BusinessRules::LintService` bloquea **activar** reglas inválidas (422 +
  `business_rule_errors`); disabled inválidas sí se guardan.
- Sanitize: `enabled` default false; normaliza `values` `{id,name}` → `["id"]`.
- Kill switch `business_rules_paused` (Guard + FE guard skip).
- Index: banner, pause toggle, dry-run vía `checkStatusChange`, create/presets
  disabled.

**Archivos:** `lint_service.rb`, `condition_values.rb`, `accounts_controller.rb`,
`business_rules_guard.rb`, `businessRules/Index.vue`,
`BusinessRulesDryRunDialog.vue`, `businessRulesLint.js`, i18n EN/ES, specs.

**Cómo probar:** AND imposible → no se puede enable; OR + categoría real → OK;
Simular Venta muestra campos; Pause → resolve sin attrs.

### B-NEW-49 — KPIs de contacto: Abiertas/Resueltas en 0, todo en Otras

**Síntoma:** ficha de contacto muestra Total correcto (ej. 7) pero Abiertas=0,
Resueltas=0 y Otras=Total, aunque el historial lista opens/resolved (p. ej.
“Vendida” = label de `resolved`).

**Causa:** `group(:status).count` devolvía claves string (`"open"`, `"resolved"`)
y el código indexaba con enteros del enum (`Conversation.statuses[:open]` → `0`).

**Fix:** normalizar cada clave a nombre de status (int → `statuses.key`, string
tal cual) y sumar `open`+`pending` / `resolved` por nombre.

**Archivos:** `contacts_controller.rb` (`set_contact_conversation_metrics`),
`docs/BUGS.md`.

**Cómo probar:** contacto con 1 open + N resolved → chips Total=N+1, Abiertas=1,
Resueltas=N, Otras=0 (snoozed van a Otras).

### B-NEW-217 — Tokens válidos, textos legibles y controles táctiles (2026-10-24)

- Archivos: `components-next/{button,checkbox,pagination}`, `components/ui/Tabs/TabsItem.vue`, `components-next/captain/assistant/BulkSelectBar.vue`, `routes/dashboard/settings/reports/ReportContainer.vue` y `modules/widget-preview/components/WidgetFooter.vue`, bajo `app/javascript/dashboard/`.
- Causa: dos colores inexistentes, textos ilegibles y controles móviles menores de 44 px.
- Arreglo: tokens existentes en Checkbox y WidgetFooter, textos legibles en claro (teal sólido, faded/outline/ghost/link, amber ghost/link y ruby link), textos informativos y área táctil mínima de 44 px en móvil; paginador adaptable. Azul y ruby sólidos conservan develop; los colores de todos los botones en oscuro también. Foco solo con focus-visible. Sin backend ni migraciones.
- Verificación: `button/specs/{ButtonContrast,TouchControls}.spec.js`; contraste con tokens reales y regresiones en UTC y America/Guayaquil. Revisar a 390 y 1280 px los controles densos y el paginador sin recortes.

### B-NEW-39 — Automation: no enviar si ventana Meta/WhatsApp cerrada

**Causa:** `send_message` / attachment creaban outbound que WA marcaba failed
fuera de la ventana 24h (Messenger/IG similar vía `can_reply?`).

**Fix:** antes de enviar (inmediato o `DeferredOutboundJob`), si
`conversation.can_reply?` es false → no crear mensaje público; dejar nota
privada (`messaging_window_skipped`) vía `SystemAuditNote`.

**Archivos:** `automation_rules/action_service.rb`,
`messages/deferred_outbound_job.rb`, `en.yml` / `es.yml`, `docs/BUGS.md`.

**Cómo probar:** conversación WA sin incoming reciente → automation con
`send_message` → sin bubble al cliente; sí nota de ventana cerrada (sin audit genérico).

### B-NEW-40 — Plantillas WA: sin inputs de variables + ReferenceError al enviar

**Severidad:** P0 prod — modal de plantillas inutilizable (con o sin variables).

**Síntoma:**
- Plantilla con `{{contact_name}}` (ej. `ventas_seguimiento`): preview OK, mensaje
  “rellene todas las variables”, **sin inputs**, Send clickeable.
- Plantilla sin variables: al Enviar →
  `ReferenceError: findComponentByType is not defined` (`templateHelper.js`).

**Causa:** tras el refactor `@chatwoot/utils` (#15001) + merge, `templateHelper.js`
hacía `export { findComponentByType, ... } from '@chatwoot/utils'` (re-export)
pero las funciones locales (`buildTemplateParameters`,
`buildTemplateButtonsSnapshot`) llamaban `findComponentByType` **sin importarlo
al scope del módulo**. En ES modules el re-export no define el binding local →
crash en init (params vacíos) y en send (snapshot).

**Fix:**
- Import local de `findComponentByType`, `COMPONENT_TYPES`, `MEDIA_FORMATS`.
- `buildTemplateParameters` delega a `buildWhatsAppProcessedParams`.
- Parser: init sin 2º arg obsoleto.

**Archivos:** `helper/templateHelper.js`, `WhatsAppTemplateParser.vue`.

**Cómo probar:** abrir `ventas_seguimiento` → input `contact_name`; rellenar y
enviar. Plantilla sin vars → Enviar sin error en consola.

### B-NEW-218 — Buscador compartido para los encabezados de ajustes

- **Problema:** cada pantalla armaba su buscador por separado; la lupa y el texto podían superponerse al cambiar la dirección del idioma.
- **Cambio:** `components-next/input/SearchInput.vue` reutiliza el campo existente, reserva espacio para la lupa en ambas direcciones y ofrece nombre accesible, tamaños y limpieza opcional. `BaseSettingsHeader.vue` lo usa sin cambiar la consulta ni el ancho del buscador.
- **Cómo comprobar:** buscar agentes y etiquetas, escribir y borrar la consulta; revisar a 390, 768 y 1280 px en ambos temas y direcciones. La lupa debe quedar separada del texto al menos 4 px. Las pruebas del componente y del encabezado cubren el valor, nombre accesible, relleno y limpieza; las capturas y mediciones del navegador quedan registradas por separado en la autoevaluación UI-S1.

### B-NEW-41 — Flows canvas: layout no persistía / re-dagre al editar

**Síntoma:** al mover nodos y refrescar, el layout volvía a dagre; editar texto
o ramas reubicaba todo; conectar sin handle adivinaba rama; edges cruzados.

**Fix (2026-07-27):**
1. `graph.ui.positions` + `viewport` en save/load (runtime ignora `ui`).
2. Rebuild estructural conserva coords; dagre solo nodos nuevos o **Auto-organizar**.
3. `onConnect` exige `btn-N` / `out`; `connectBranch` ya no adivina rama.
4. Alturas por #botones, snap 16px, MiniMap si <40 steps, rama rota en ámbar.

**Archivos:** `FlowCanvas.vue`, `Edit.vue`, `FlowStepNode.vue`, `flow.rb`,
`en`/`es` flows.json, `FEATURE_CONVERSATION_FLOWS.md`.

**Cómo probar:** mover nodos → Guardar → F5 mismas posiciones; editar mensaje
sin salto; conectar desde botón 2; Auto-organizar + Guardar.

### B-NEW-42 — Flows: encadenamiento index+1 + preview por paso

**Síntoma:** paso sin botones seguía al siguiente por orden en el array
(`steps[index + 1]`), aunque otra rama ya hubiera ramificado; conectar handle
`out` reordenaba el array en lugar de guardar destino.

**Fix (2026-07-27):**
1. `step.next` (`end` | `handoff` | stepId) en editor; default `end` en pasos nuevos.
2. `buildGraph` / `nodeToStep` / `connectBranch` usan destino explícito (sin splice).
3. Canvas `linearTarget`, `structureKey` con `next`, rama rota en ámbar.
4. Inspector: select **Después de las acciones**. Botón ℹ️ del header abre
   diálogo con resumen de todos los pasos (no panel por paso).

**Archivos:** `Edit.vue`, `FlowCanvas.vue`, `FlowStepInspector.vue`,
`FlowHeader.vue`, `FlowOverview.vue`, `flowStepSummary.js`, `en`/`es` flows.json,
`FEATURE_CONVERSATION_FLOWS.md`.

**Cómo probar:** 3 pasos — Paso 1 con 2 botones → 2 y 3; Paso 2 sin botones,
`next = Fin` → no encadena a 3 en canvas ni runtime; select ↔ handle `out`;
preview en vivo; Guardar + F5; flujo viejo carga `next` desde edge lineal.

### B-NEW-43 — Franja Panel IA queda pegada tras asignar humano

**Severidad:** Bug UX — listado muestra rojo/`solicita_ayuda` aunque un agente
humano ya atiende.

**Síntoma:** tras handoff, `custom_attributes.panel_ia_estado` queda en
`solicita_ayuda`. Al asignar un User la franja lateral sigue visible porque
`usePanelIaState` priorizaba el attr aunque `isBotHandled` fuera false.

**Nota:** `panel_ia_*` no es Custom Attribute Definition (Settings); es JSON
interno en `conversation.custom_attributes` (Panel AI / Flows).

**Fix:**
- FE: si `isHumanAssigneeMeta` → sin indicador.
- Rails: al asignar User en `Conversations::AssignmentService`, borrar
  `panel_ia_estado` / `_label` / `_updated_at` (no al asignar AgentBot).
- Leyenda de colores en Settings → Bots y Settings → Flows.

**Archivos:** `usePanelIaState.js`, `assignment_service.rb`,
`PanelIaStateLegend.vue`, `agentBots/Index.vue`, `flows/Index.vue`,
`en/conversation.json`.

**Cómo probar:** conv con franja roja → asignar humano → franja desaparece;
reasignar bot → vuelve según estado. Settings Bots/Flows muestran leyenda.

---

### B-NEW-44 — Calendar: fixtures de invitación desactualizados tras merge de develop

- **Archivo:** `spec/lib/integrations/google_calendar/event_service_invitation_text_spec.rb`.
- **Causa:** nombre visible aleatorio en la fábrica de usuarios, asistente simulado sin `id` y stub de `update_description` que devolvía `nil`.
- **Fix:** fijar `display_name`, usar la fábrica real de Captain y devolver descripción/etag como hash del cliente. Sin cambios de código de producto.
- **Test:** ejecutar el spec completo; verificar nombre visible humano, nombre del asistente y completar la invitación con el enlace Meet.

---

## 5b. UX fijados (reply / plantillas WA)

### UX-001 — Preview reply-to en notas privadas

`ReplyBox.vue` — `shouldShowReplyToMessage` muestra preview en modo nota.

### UX-002 — Botones plantilla WA en bubble

Snapshot `content_attributes.template_buttons` + render en `Text/Index.vue`.

---

## 6. Cómo probar (smoke post-auditoría)

```powershell
# Ruby (montado en ./app) — restart
docker compose -f docker-compose.dokploy.yml -f docker-compose.dokploy.fork.yml restart chatwoot-rails chatwoot-sidekiq

# Vue (claim 409 alert) — rebuild
docker compose -f docker-compose.dokploy.yml -f docker-compose.dokploy.fork.yml up -d --build chatwoot-rails
```

1. Soft-cancel/destroy task vía API como assignee → 200 (antes 403).
2. Task asignada a team A: agent de team B **no** recibe ActionCable create/update.
3. Claim concurrente → uno 200, otro 409 + alert FE.
4. Agente no assignee/no team: hilo **y** timeline ocultan notas privadas ajenas.
5. Nested `/conversations/:id/internal_tasks` solo lista tasks visibles por policy.
6. Navegar `/tasks` sin errores de consola.

---

## 7. Próximos pasos

1. Smoke manual items 1–6 arriba.
2. Commit/push a PR #3 cuando se pida.
3. Diseñar chats grupales reutilizando cable scoped + PrivateNoteVisibility / futura NotePolicy.
4. Specs mínimos: claim lock, destroy policy, PrivateNoteVisibility (recomendado antes de merge a prod).

---

### B-NEW-55 — Flow catalog CI: Rails parameters and reactive filters

`app/controllers/api/v1/accounts/whatsapp_flows_controller.rb`: filter validation called `any?` on `ActionController::Parameters`, which is not a Hash/Enumerable. Iterate its `each_pair` enumerator instead. This fixes the 500 before both index and paginated publication_status, including invalid filters; missing `payload`/`rows` in failing assertions were downstream effects. Preserve the payload wrapper, newest-first ordering and legacy publication_status response. Request regressions cover empty accounts/WABAs and nested invalid filter objects.

`FlowsPanel.vue` and `FlowPublicationPanel.vue`: use Vue's `watch` with `useDebounceFn` instead of VueUse's external `watchDebounced`. The latter missed changes with CI's dependency loading; the previous local harness inlined VueUse and masked that difference. Before: six failures in the two panel suites using CI dependency settings; after: all 17 panel tests pass without changing their expectations.

`spec/services/whatsapp/flows/publication_catalog_spec.rb`: use numeric WABA fixtures, including the disconnected WABA; `"removed"` violates the real publication model's numeric-ID validation and raised RecordInvalid. No production validation was relaxed. RSpec cannot run locally; PM verifies Rails requests and RuboCop/CI.

### B-NEW-54 — ComboBox viewport anchoring and dialog Escape

`components-next/combobox/ComboBox.vue` uses the shared `useDropdownPosition` for local and teleported menus, including viewport flipping and scroll/resize tracking. `ComboBoxDropdown.vue` prevents Escape's native dialog cancellation while closing the menu. The original Flow control was placed directly above the properties panel; moving it to the header removes that overlap (the reported displacement was not reproduced).

Validation: ComboBox and ReorderableMultiSelect Vitest suites, including multiselect, footer/group empty states, numeric values, keyboard focus and viewport anchoring/flip. Open header categories and scroll/resize; Escape closes the menu and keeps the creation dialog open.

### B-NEW-53 — WhatsApp forms: stale publication and editor preview clarity

- Files: `WhatsappFlowSendDialog.vue`, `WhatsappFlowSend.vue`, `WhatsappFlowsController`, `FlowsPanel.vue`,
  `FlowBuilderPage.vue`, `FlowPhoneCanvas.vue`, `useFlowPublications.js`, and English/Spanish `whatsappFlows.json`.
- Sending uses the first eligible form and default bubble text, with collapsed customization and a live bubble preview.
  The composer no longer repeats the closed 24-hour-window notice. Bubble text limits and emoji restrictions apply before sending.
- The API derives `unpublished_changes` from publication timestamps without a migration; the list and builder expose it.
  Publishing explains Meta's immutable form content and ChatHub's replacement version and deprecation request.
- Starting models belong to the editor, outside the customer phone canvas. Actual definition screens remain intact.
- Verify: open the send dialog, expand customization and edit all three bubble fields; check the closed-window notice once.
  Edit and save a published form, check the list badge and builder banner, republish and refresh publication status.
  On a new form, choose a starting model outside the phone and verify its customer fields appear inside the phone.

### B-NEW-54 - Outgoing WhatsApp Flow/template identity

- Files: `components-next/message/Message.vue`, `bubbles/WhatsappFlowSent.vue`, `bubbles/WhatsappTemplate.vue`,
  `Message`, `Whatsapp::TemplateMessageSnapshotService`, and the message JSON partial.
- Outgoing Meta Flows show their stored name, header/body and CTA. WhatsApp templates show identity/category,
  header, body, footer and informative buttons. Private/deleted/CSAT/Twilio messages keep their existing selection.
- New template messages store an additive visual snapshot after Liquid rendering at the common Message creation callback,
  including manual sends, automations and direct Captain sends. HTTP and dashboard events expose only visual template/Flow metadata.
  Internal template parameters and Flow tokens are excluded from that projection. No migration or backfill.
- Verify: send a Flow or approved template, reload the conversation, compare manual and automation sends, and check light/dark.
  Check a template with an image header and quick-reply/URL/Flow buttons; labels have no actions. Historical plain text stays plain.
- Coverage: Vitest bubbles/selection plus RSpec snapshots, Captain reminder/reengagement and HTTP projection examples.

### B-NEW-56 — Meta template library root endpoint and language fallback

- Files: `app/services/whatsapp/template_management_service.rb`, `inbox_whatsapp_templates_controller.rb`,
  `settings/templates/LibraryPanel.vue`, English/Spanish `whatsappTemplateMgmt.json`, and their service/request/Vitest specs.
- The Predefinidas tab called the WABA's `/message_template_library`, which Graph v22.0 rejects as a nonexistent field.
  The library now uses the Graph root endpoint, with the same token, filters and `after` cursor.
- Regional Spanish requests map to `es`; supported regional library codes `en_US` and `pt_BR` are preserved.
  A GET rejected with Meta's specific unavailable-library-language error retries in `en_US`, then without language.
  Other errors propagate immediately. The response exposes `language_used` (`null` means all available languages).
- Creation stays at the WABA's `/message_templates`, uses the same language mapping and reports `language_used`.
  Writes are never retried. Meta's `error_user_msg` or `message` reaches the UI, with a Spanish/English library error context.
- Verify: open Predefinidas with an `es_EC` inbox, check Spanish results and the actual language label, load another page,
  then create a library template and check the Spanish creation confirmation. Force a Meta refusal and check its real text.
- Regression coverage: WebMock root/auth/filters/cursor, mapping/fallback order/final errors and creation; request response/status
  contracts; LibraryPanel actual language, creation confirmation and Meta error text. Rails/RuboCop require PM CI verification
  because the host has no Ruby and this task forbids Docker.

### B-NEW-57 — Template library CI query matcher types

- File: `spec/services/whatsapp/template_management_service_spec.rb`.
- CI run `37707033360`, job `backend-tests (16, 5)`, failed both library fallback examples before the first response:
  WebMock's partial query matchers expected integer `limit: 25`, while the decoded HTTP query contained string `"25"`.
- Match the serialized limit as a string in both partial query stubs. Production behavior stays unchanged;
  the examples still check preserved filters/pagination and the Spanish → US English → all-languages retry order.
- Verify: rerun the two `#library` fallback examples at lines 235 and 249 in CI. RSpec cannot run locally;
  check the changed Ruby file with the CI RuboCop Docker image.

### B-NEW-58 — Library cancellation spec retained a removed inbox selection

- File: `settings/templates/specs/LibraryPanel.spec.js`.
- CI run `37722942084` failed only the superseded-response frontend example. It replaced inbox 5 with inbox 6
  while the selected inbox remained 5, then expected inbox 6's response language to be displayed.
- Refresh the same selected inbox instead, and wait for the filter update before asserting one current row,
  no stale rows, and the current Spanish language rather than the superseded US English response.
- Production counted filters, inbox destinations, language reporting and Meta errors remain unchanged.
- Verify: run the LibraryPanel Vitest suite; all backend shards and RuboCop passed in the failing CI run.

### B-NEW-221 — Nombres operativos ambiguos entre Flows y ajustes

- Problema: la navegación, el editor y el retorno podían llamar «Flow» tanto al recurso de WhatsApp como al de conversación; los límites de seguridad y la regeneración del token tenían nombres poco precisos.
- Archivos: `app/javascript/dashboard/i18n/locale/en/{settings,integrations,automation,flows,whatsappFlows}.json` y `app/javascript/dashboard/routes/dashboard/settings/flows/FlowHeader.vue`.
- Cambio: contexto explícito para cada tipo de Flow, límites de seguridad, perfil y políticas, conservando claves, rutas, marcas y datos propios. Las traducciones existentes se sincronizan por Crowdin. Las acciones del editor pueden pasar a otra línea en móvil para mostrar sus textos completos.
- Verificación: compilar los catálogos y recorrer navegación, editor, guardar y volver en ambos idiomas; comprobar las pruebas del glosario y del encabezado.

### B-NEW-59 -- Editing positional WhatsApp templates changed their Meta structure

- Files: `settings/templates/TemplateFormDrawer.vue`, `templateForm.js`, `Index.vue`,
  `Whatsapp::TemplateManagementService`, `Whatsapp::TemplateComponentsBuilder`,
  `Whatsapp::TemplateEditValidator`, `inbox_whatsapp_templates_controller.rb`, en/es translations and related specs.
- Regression: editing `test_utility_envio` replaced four POSITIONAL variables with three NAMED variables,
  added a header and encoded the dynamic URL placeholder, leading to a Meta 422.
- Load the live Meta components, format, examples and update time. Keep edit identity, component types,
  button types and the full parameter sequence; reject structural changes before a write to Meta.
  Create a separate NAMED copy through explicit system-variable ComboBoxes and a different editable name.
- Keep `https://paluhub.com/track/{{2}}` unencoded and require a complete matching example URL.
  Return the original Meta message/code/subcode/user message, show it in the drawer and warn-log only
  whitelisted fields with credentials and submitted text/examples redacted.
- Verify: edit the approved positional preset without a header/footer; check all four examples, the single
  approval warning and the raw URL. Try adding/removing/reordering parameters. Open the system copy,
  complete each mapping and confirm only the new template is created. Reject a save and check the inline Meta error.
- Local validation: 60 isolated RSpec/WebMock service/builder examples pass; the full template Vitest folder
  and subsequent drawer regressions pass. CI RuboCop changed-line filtering passes on all seven Ruby files.
  The real-controller Rails request specs are authored but cannot run in the available production-only image.
  Full Vite build is blocked by the documented old `@chatwoot/prosemirror-schema` missing `imagePastePlugin` export.

### B-NEW-60 -- Template last edit displayed a raw ISO timestamp

- Files: `settings/templates/TemplateFormDrawer.vue` and its drawer spec.
- Format the live last edit with the user's resolved locale and local timezone; hide missing or invalid dates.
- Verify: open the positional edit preset in Spanish/Guayaquil and check `7 oct 2026, 05:00`;
  check the Meta error state too. Template Vitest folder: 277 tests pass; ESLint and Prettier pass.

### B-NEW-61 -- Template copy mapping excluded attributes and Captain variables

- Files: `settings/templates/TemplateFormDrawer.vue`, `templateForm.js`, drawer specs and en/es template strings.
- Reuse the editor's grouped variable source for copy mappings, including contact/conversation attributes and Captain.
  Validate against those available names, preserving distinct mappings. Rename the action to "Create copy with variables".
- Reuse the Flow picker's ComboBox footer and existing attribute modal for administrators; refresh bindings on close.
- Verify: map a positional copy to system, contact, conversation and appointment variables; submit creates only the NAMED copy.
  Search the grouped picker, open/close the attribute modal, and check the CTA is absent for agents.

### B-NEW-62 -- Template variable picker differed from Flow and long menus covered the footer

- Files: `settings/templates/TemplateFormDrawer.vue`, local `TemplateComboBox.vue`, drawer specs and en/es group labels.
- Replace the remaining variable `DropdownMenu` with ChatHub's ComboBox. Give every drawer selector a local teleport
  target, explicit placeholders, consistent search behavior and shared trigger/list styling. Long menus scroll inside
  the panel body; search and the attribute CTA stay visible above the drawer footer.
- Verify: new/edit/copy selector specs; 285 template tests pass. Actual Flow/drawer browser comparison verifies matching
  trigger, option and group appearance and no footer overlap. See `docs/TEMPLATE_PICKER_AUDIT.md` for the audit table.

### B-NEW-222 — Errores de validación en inglés en Captain y equipos

- Problema: los ajustes básicos y de sistema de Captain y el nombre de equipo mostraban los mensajes predeterminados de Vuelidate aunque la interfaz estuviera en español.
- Archivos: `AssistantBasicSettingsForm.vue`, `AssistantSystemSettingsForm.vue`, `settings/teams/TeamForm.vue`, `settings/teams/helpers/validations.js` y catálogos `en/es/general.json`.
- Cambio: mensajes localizados y reactivos para obligatorios, longitudes, mínimos, máximos y enteros mediante `helpers.withMessage`; se conservan límites, campos opcionales, condiciones y tipos del payload.
- Verificación: `LocalizedSettingsValidation.spec.js` comprueba ambos idiomas, fronteras y cambio de idioma; revisar ajustes básicos y de sistema y crear/editar equipos con datos inválidos y válidos.

### B-NEW-63 -- Shared filter menus stayed behind native dialogs

- Files: `components-next/dropdown-menu/MenuPopover.vue` and its spec.
- Use the existing dialog portal target so the real DropdownMenu remains in the native top layer.
  Keep fixed positioning and the same stacking level as ComboBox; body portals remain the default.
- Verify: open category/status filters in the send center and assignment menus in a task dialog.
  Confirm the menu receives clicks, does not move the trigger, and Escape restores focus.

### B-NEW-66 -- Login redesign (photo panel, pill form, Google/SSO) and password visibility reactivity

- Files: `v3/views/login/Index.vue`, `v3/components/Form/Input.vue`, `v3/components/Form/WithLabel.vue`,
  `v3/components/GoogleOauth/Button.vue`, login hero image, `en|es/login.json` and auth form specs.
- Two-column login: full-height hero photo with brand logo, serif headline and separate top/bottom gradients;
  right column with label-less pill inputs, black pill button, OR divider, Google and SSO pill buttons, and a
  "Sign up for free" link when account signup is enabled.
- Keep password visibility in a native Vue ref. The local dependency tree resolves VueUse against Vue 3.5.13
  while the component uses Vue 3.5.12; its toggle changed a ref without updating the rendered input.
- Restrict the new password padding/button sizing to outlined inputs, preserving the default signup/SAML styling.
- Google needs `GOOGLE_OAUTH_CLIENT_ID`, SSO needs a non-community plan and signup needs `ENABLE_ACCOUNT_SIGNUP=true`;
  the login language follows the server `DEFAULT_LOCALE` (or `?locale=`), there is no selector.
- Verify: check the hero at 1280x720, 1440x900 and 1920x1080; click the real password button twice and confirm
  input type, eye icon, pressed state and value. Run all v3 specs, including signup labels/eye and SAML POST/validation.

### B-NEW-67 — Registro y Captain: errores recuperables del onboarding (ONB-02/03/07/11)

- Archivos: `components-next/captain/pageComponents/assistant/CreateAssistantDialog.vue`,
  `dashboard/store/utils/api.js`, `v3/views/auth/confirmation/Index.vue`,
  `v3/views/auth/signup/components/Signup/Form.vue`, `dashboard/i18n/locale/{en,es}/signup.json`
  y sus specs `CreateAssistantDialog.spec.js`, `store/utils/specs/api.spec.js`,
  `auth/confirmation/Index.spec.js` y `Signup/Form.spec.js` (rutas bajo `app/javascript/`).
- Causa: el diálogo capturaba el rechazo de creación y continuaba mostrando éxito;
  la confirmación redirigía incluso con token inválido; el parser devolvía objetos o
  errores de transporte sin payload; captcha fallaba sin explicación y el cliente
  exigía correo empresarial aunque el servidor acepta correos personales.
- Cambio: crear Captain solo cierra y emite éxito tras guardar; conserva el error del
  servidor y permite reintentar. La confirmación fallida ofrece entrar o reenviar a un
  correo válido mediante `resend_confirmation`, con captcha y respuesta neutra.
  El parser entrega solo mensajes de texto del payload y permite el fallback traducido
  de la UI; registro muestra un mensaje genérico o uno específico de captcha.
  Se aceptan Gmail y otros correos personales; el servidor conserva el bloqueo de desechables.
- Verificar: agotar el límite del plan o simular 4xx/5xx al crear Captain: el diálogo
  conserva los datos, muestra un único error y permite reintentar sin falso éxito.
  Abrir enlaces de confirmación inválidos, caducados o usados: comprobar las dos acciones,
  reenviar con y sin captcha y verificar que el mensaje no revela si existe la cuenta.
  Registrar Gmail; simular rechazo de correo desechable y comprobar el mensaje del servidor.
  Simular error de red/sin payload y captcha fallido/caducado: comprobar textos en inglés
  y español y que vuelve a ser posible enviar el formulario.
- Cobertura: specs del diálogo (rechazo, reintento y edición), confirmación (error,
  éxito y reenvío), registro (Gmail, desechable, fallback y captcha) y parser (payloads
  válidos y errores sin mensaje utilizable). ESLint: 0 errores. Vitest con
  `vitest.local.config.ts`, incluyendo `dashboard/i18n`, no inicia por `spawn EPERM`
  de esbuild en este entorno; pendiente de ejecución por el PM.

### B-NEW-68 — Registro con el layout del login y requisitos de contraseña dentro de la columna

- Archivos (bajo `app/javascript/`): `v3/components/Auth/AuthSplitLayout.vue`,
  `v3/views/login/Index.vue`, `v3/views/auth/signup/Index.vue`,
  `v3/views/auth/signup/components/Signup/{Form,PasswordRequirements}.vue`,
  `v3/views/auth/verify-email/Index.vue`, `v3/components/GoogleOauth/Button.vue`,
  `v3/components/Form/Input.vue`, `dashboard/i18n/locale/{en,es}/{signup,login}.json`
  y los specs indicados abajo.
- Causa: registro conservaba el diseño anterior, los requisitos de contraseña se
  mostraban en un popup lateral y había textos en inglés en español. El botón de
  Google ignoraba el slot de registro y no explicaba que después se define una contraseña.
- Cambio: login, registro y verificación comparten la foto, los degradados, los logos
  por tema, la columna de 480 px y el comportamiento móvil. Registro conserva sus
  dos campos actuales (correo y contraseña), el contrato del API, captcha, términos,
  errores y ruta de verificación. Usa campos outlined de 56 px, botón principal
  píldora y requisitos siempre visibles con checks reactivos dentro de la columna.
  Google solo aparece si está habilitado y tiene client ID, acepta texto por slot
  y explica el siguiente paso. Se completan los textos de registro en inglés/español
  y las etiquetas accesibles del botón de mostrar/ocultar contraseña.
- Cobertura (bajo `app/javascript/`):
  - `v3/components/Auth/AuthSplitLayout.spec.js`: foto, degradados, marca, logos
    claro/oscuro y fallback, panel móvil oculto y columna compartida.
  - `v3/views/login/Index.spec.js`: montaje del login real con el layout compartido;
    conserva los casos existentes de validación, OAuth, SSO, MFA y sesiones.
  - `v3/views/auth/signup/Index.spec.js`: montaje completo en inglés/español,
    titulares, campos existentes, etiquetas accesibles, medidas, términos y enlace al login.
  - `v3/views/auth/signup/components/Signup/Form.spec.js`: cinco requisitos en vivo,
    envío válido/inválido, contrato y ruta, Google condicional y aviso, errores de API,
    captcha y spinner con bloqueo de envíos repetidos.
  - `v3/components/GoogleOauth/Button.spec.js`: etiqueta de login por defecto,
    slot de registro y URL OAuth sin cambios.
  - `v3/components/Form/Input.spec.js` y `v3/views/auth/AuthForms.spec.js`:
    visibilidad y etiquetas de contraseña en ambos idiomas, variante outlined de
    registro y compatibilidad de los campos y el POST de SAML.
  - `v3/views/auth/verify-email/Index.spec.js`: layout y textos en inglés/español,
    reenvío neutro, captcha, errores/reintento, spinner y retorno al login sin email.
  - `dashboard/i18n/messagesCompile.spec.js`: compilación de mensajes de ambos idiomas.
- Verificar manualmente: abrir registro y login en escritorio y móvil, con tema
  claro/oscuro; comprobar misma foto y medidas, requisitos sin desbordes y Google
  solo con configuración válida. Registrar correo, revisar la pantalla de verificación,
  reenviar y completar el flujo existente de confirmación.
- Validación local: ESLint de los archivos JS/Vue tocados sin errores. El comando
  `npx vitest run --config vitest.local.config.ts app/javascript/v3 app/javascript/dashboard/i18n`
  no inicia: esbuild devuelve `spawn EPERM`. Specs, build y capturas pendientes del PM.

### B-NEW-69 — Datos del negocio en el paso 2 del onboarding (ONB-01/06/10/13)

- Archivos: `app/javascript/dashboard/routes/dashboard/onboarding/Index.vue`,
  `account-details/{OnboardingFormSelect.vue,useAccountEnrichment.js}` dentro de esa
  carpeta, `app/controllers/api/v1/accounts/onboardings_controller.rb`,
  `app/javascript/dashboard/i18n/locale/{en,es}/onboarding.json` y los specs indicados abajo.
- Causa: la web era obligatoria, el nombre del negocio no se podía editar y los
  selectores nativos y las traducciones incompletas dificultaban el primer ingreso.
- Cambio: «Cuéntanos de tu negocio» reutiliza `AuthSplitLayout` con foto y columna,
  campos y botón de 56 px con forma de píldora, temas claro/oscuro y disposición móvil.
  Muestra «Paso 2 de 5» con progreso visual. El nombre se precarga y permite edición;
  el tipo se elige entre cuatro tarjetas obligatorias. País y web son opcionales;
  país y zona horaria usan ComboBox con búsqueda y nombres de países localizados
  desde la lista compartida (se excluye el código retirado AN). Zona horaria se
  detecta en el navegador; idioma ofrece es/en y prefiere el de la cuenta.
  Se retiran rol, sector, tamaño y origen de la pantalla, conservando su contrato backend.
  Se eliminan `account-details/OnboardingFormRow.vue` y `shared/constants.js`,
  que solo usaba el formulario anterior.
  Se mantiene la espera del enriquecimiento y se protegen los campos editados frente
  a sus actualizaciones tardías. Los errores usan la alerta existente y conservan los datos.
  El backend guarda `business_type` y `country` en atributos personalizados y devuelve
  422 para tipos fuera del catálogo o países fuera de ISO 3166 mediante TZInfo.
  No cambia rutas, guards, permisos ni transiciones: cloud sigue a `inbox_setup`;
  instalación propia finaliza. No implementa los pasos futuros ni modifica Captain.
  Se completan en/es y se corrigen los controles ingleses y Outlook en español.
- Cobertura:
  - `app/javascript/dashboard/routes/dashboard/onboarding/specs/Index.spec.js`:
    layout/campos/textos en ambos idiomas, progreso, nombre editable, tipo obligatorio,
    web y país opcionales, precargas de zona/idioma, ComboBox y selecciones;
    envío mediante la acción real del store a `OnboardingAPI.update` con
    `onboarding_step: account_details`, normalización de web, rutas cloud/propia,
    errores/reintento sin pérdida de datos, carga y bloqueo de envíos repetidos.
  - `app/javascript/dashboard/routes/dashboard/onboarding/specs/account-details/useAccountEnrichment.spec.js`:
    precargas, preferencia del idioma de la cuenta, espera/timeout y protección del
    nombre editado y de una web borrada frente al enriquecimiento tardío.
  - `spec/controllers/api/v1/accounts/onboardings_controller_spec.rb`: guardado del
    nombre/tipo/país sin web, cuatro tipos válidos, país vacío y rechazo 422 sin
    persistencia ni avance para tipo inválido/malformado o país inválido. Conserva
    los casos existentes de autorización, compatibilidad y transiciones cloud/propia.
  - `app/javascript/dashboard/i18n/messagesCompile.spec.js` (existente): compila
    todas las hojas en/es, incluyendo los nuevos mensajes de onboarding.
- Verificar manualmente: abrir onboarding en escritorio y móvil, claro/oscuro;
  editar el nombre, seleccionar un tipo, buscar país/zona, confirmar idioma y
  continuar sin web. Simular fallo de API y comprobar que permite reintentar con
  los mismos datos. Verificar la salida existente en cloud e instalación propia.
- Validación local: ESLint de los JS/Vue tocados sin errores ni advertencias;
  compilación directa de ambos componentes Vue y de los 93 mensajes por idioma,
  con igualdad de claves en/es. El comando solicitado
  `npx vitest run --config vitest.local.config.ts app/javascript/dashboard/routes/dashboard/onboarding app/javascript/v3 app/javascript/dashboard/i18n`
  no inicia: esbuild devuelve `spawn EPERM`. Ejecución de specs, build y capturas
  pendientes del PM; RSpec no se ejecuta localmente, queda para CI. Sin migraciones.

### B-NEW-70 — Contraste, formulario compacto y selección accesible del negocio (ronda 2)

- Archivos: `app/javascript/v3/components/Auth/AuthSplitLayout.vue`,
  `app/javascript/dashboard/routes/dashboard/onboarding/Index.vue`,
  `account-details/{OnboardingFormSelect.vue,timezoneOptions.js}` dentro de esa carpeta,
  `app/javascript/dashboard/components-next/combobox/ComboBox.vue`,
  `app/controllers/api/v1/accounts/onboardings_controller.rb` y sus specs.
- Cambio: el titular y subtítulo sobre la foto declaran blanco explícitamente.
  El paso de negocio usa una columna con scroll interno y un pie fuera del scroll
  para mantener «Continuar» visible, asociado al formulario mediante `form`.
  Se reducen separaciones y se colocan país e idioma juntos desde 640 px, apilados
  en móvil. Los ComboBox usan portal para evitar recortes por el área de scroll.
  Las zonas conservan el identificador IANA y muestran país localizado con
  `Intl.DisplayNames`, offset calculado con `Intl.DateTimeFormat` y ciudad;
  la búsqueda admite ciudad, países asociados e identificador.
  Las tarjetas conservan su altura mínima, añaden iconos Lucide, selección con
  borde/fondo de marca y check; exponen radios con un único punto de tabulación
  y flechas que cambian selección y foco, incluyendo el salto entre extremos.
  La validación Ruby extrae predicados y usa `exclude?` y modificadores `if`,
  conservando el contrato y los specs del controlador. Sin cambios de textos i18n.
- Cobertura: specs del onboarding para pie/scroll, disposición responsive,
  asociación y envío del formulario desde el pie, radios/foco y búsqueda IANA;
  nuevo `specs/account-details/timezoneOptions.spec.js` para nombres localizados,
  horario de verano, alias guardados y offsets fraccionarios. Se amplían
  `AuthSplitLayout.spec.js` y `combobox/specs/ComboBox.spec.js` para contraste y búsqueda.
- Verificar manualmente: abrir a 1440×900, 1280×720 y en móvil; comprobar el pie
  visible, foto inmóvil, menús sin recortes y selección por teclado en ambos temas.
- Validación local: ESLint de todos los JS/Vue tocados sin errores ni advertencias.
  Compilación directa de los cuatro componentes Vue modificados y los 93 mensajes
  de onboarding por idioma (en/es); comprobación directa del formateador sobre
  419 zonas, alias IANA, horario de verano y offsets fraccionarios, correcta.
  El comando de Vitest solicitado sigue bloqueado al arrancar por `spawn EPERM`
  de esbuild; RuboCop y RSpec no pueden ejecutarse porque Docker no está disponible
  y el host no tiene Ruby. Ejecución de specs y comprobación visual pendientes.
  Sin migraciones ni commit.

#### Paso 3 — Conecta tu WhatsApp (ampliación de B-NEW-70, 2026-10-17)

- Ronda 4: `InboxSetup.vue` llena el estado inicial con tres pasos traducidos en
  en/es e iconos Lucide sobre círculos suaves, centrados en el espacio disponible.
  La falta de configuración muestra una nota neutra con icono de información y
  «Usar otro canal» como botón secundario de borde en el pie; «Lo haré después»
  conserva su aspecto de enlace. El éxito mantiene la tarjeta con un check más
  grande sobre fondo teal y «Continuar» como único botón primario. Se conserva
  el contenido desplazable separado del pie sin superponerlo. Specs ampliados
  para pasos en ambos idiomas, nota/acciones y transición de no disponible a
  canal conectado. ESLint: 0 errores y advertencias; scripts/templates Vue y
  113 mensajes por idioma compilados, claves en/es iguales y generación de
  iconos/tokens Tailwind verificada. Vitest de onboarding/i18n/AuthSplitLayout
  bloqueado por `spawn EPERM` (esbuild; también resolución de rutas de Vite al
  intentar carga sin esbuild). La herramienta de navegador no inicia por acceso
  denegado al sandbox de Windows: revisión visual pendiente en los tres estados,
  móvil/escritorio y claro/oscuro; comprobar que no haya scroll horizontal y que
  todo el contenido pueda alcanzarse sin quedar detrás del pie. Sin commit.
- Ronda 3: `onboarding_version` se serializa solo si está presente en `custom_attributes` de la cuenta (GET/PATCH y avance del onboarding) y en cada membresía de sesión/perfil/creación de cuenta; esta última respuesta también omitía `onboarding_step` y ahora lo expone, sin publicar otros atributos internos. Specs de requests cubren v2, legado, múltiples cuentas, avance y finalización; se corrigen el condicional y el contexto anidado de RuboCop en Embedded Signup. ESLint: 0 errores, 2 advertencias de claves dinámicas i18n; RSpec/RuboCop pendientes por acceso denegado al motor Docker. Sin cambios frontend en esta ronda.
- Ronda 2: solo en onboarding v2, el administrador actual se incorpora con `Inbox#add_members` a las bandejas sin miembros al completar u omitir `inbox_setup` y al crear por Embedded Signup; es idempotente y conserva miembros existentes. «Usar otro canal» cierra el diálogo de WhatsApp al conectar y muestra el éxito con «Continuar» y el aviso de asignación en en/es, sin pasar por agentes ni cambiar Ajustes. Cobertura RSpec del servicio y endpoints, y Vitest del diálogo y éxito; ESLint sin errores. Vitest bloqueado al iniciar por `spawn EPERM`; RSpec pendiente porque Docker no está disponible.
- Problema: ONB-04/05/08/11. El primer canal guiado solo aparecía en cloud,
  se creaba un widget antes de elegir WhatsApp y faltaban estados recuperables.
- Cambio: cuentas nuevas de `AccountBuilder` reciben `onboarding_version: 2`.
  Después del negocio pasan a `inbox_setup` en cloud e instalaciones propias,
  sin crear widget ni centro de ayuda. Las cuentas sin versión conservan el
  recorrido anterior. La API v2 respeta el nuevo cursor y conserva su contrato
  anterior para cuentas sin versión.
- Pantalla: `AuthSplitLayout`, Paso 3 de 5, botones píldora y tokens de tema.
  Reutiliza el Embedded Signup con coexistencia existente; muestra carga,
  cancelación, error traducido con reintento, éxito con nombre/número del API
  y falta de configuración. «Usar otro canal» abre el diálogo existente y
  «Lo haré después» permite salir incluso durante la conexión. Continuar u
  omitir actualiza la sesión y entra al dashboard. No implementa pasos 4/5.
- Persistencia: `inbox_setup_result` solo admite `whatsapp_connected` o `skipped`
  para completar la versión 2; valores ausentes/malformados devuelven 422.
  Replays y solicitudes fuera de orden siguen siendo no-op, sin sobrescribir
  el resultado. El guard sigue el cursor y la pantalla espera la carga de la
  cuenta al recargar antes de recuperar las bandejas conectadas.
- Archivos de producto:
  - `app/builders/account_builder.rb`.
  - `app/controllers/api/v1/accounts/onboardings_controller.rb`.
  - `app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb`
    (añade `phone_number` a la respuesta existente).
  - `app/controllers/api/v2/accounts_controller.rb`.
  - `app/javascript/dashboard/routes/index.js`.
  - `app/javascript/dashboard/routes/dashboard/onboarding/InboxSetup.vue`,
    `LegacyInboxSetup.vue` (pantalla anterior preservada) e `Index.vue`
    (refresca la sesión antes de avanzar).
  - `app/javascript/dashboard/i18n/locale/{en,es}/onboarding.json`.
- Cobertura añadida/ampliada:
  - `app/javascript/dashboard/routes/dashboard/onboarding/specs/InboxSetup.spec.js`:
    estado inicial, carga/doble clic, éxito y credenciales de coexistencia,
    cancelación, errores SDK/API traducidos y reintento, omitir, otro canal,
    configuración ausente/restricción/flag cloud, continuar, recarga, carga
    asíncrona de cuenta, error al finalizar y compatibilidad de pantalla anterior.
  - `app/javascript/dashboard/routes/dashboard/onboarding/specs/onboardingGuard.spec.js`:
    redirección según cursor, recarga, orden, finalización y usuarios no elegibles.
  - `app/javascript/dashboard/routes/dashboard/onboarding/specs/Index.spec.js`:
    actualiza su expectativa de refresco de sesión al avanzar al canal.
  - `spec/controllers/api/v1/accounts/onboardings_controller_spec.rb`:
    versión 2 en cloud/propia, ausencia de widget, resultados válidos,
    rechazo de valores inválidos, replays y orden. Conserva los casos legacy.
  - `spec/enterprise/controllers/api/v1/accounts/onboardings_controller_spec.rb`:
    versión 2 no crea widget ni centro de ayuda; conserva cobertura legacy.
  - `spec/builders/account_builder_spec.rb`: nuevas cuentas reciben versión 2.
  - `spec/controllers/api/v2/accounts_controller_spec.rb`: cursor de versión 2
    y contrato sin versión.
  - `spec/controllers/api/v1/accounts/whatsapp/authorizations_controller_spec.rb`:
    respuesta con número y nombre de la bandeja real.
  - `app/javascript/dashboard/composables/spec/useWhatsappEmbeddedSignup.spec.js`
    (existente, sin cambios): protocolo de coexistencia y finalización con WABA.
- Validación: ESLint de los JS/Vue tocados sin errores ni advertencias;
  compilación directa de script/template de las tres vistas y de los 109 mensajes
  por idioma, con igualdad de claves en/es. El comando solicitado
  `npx vitest run --config vitest.local.config.ts app/javascript/dashboard/routes/dashboard/onboarding app/javascript/dashboard/composables app/javascript/v3 app/javascript/dashboard/i18n`
  se detiene antes de ejecutar specs: esbuild devuelve `spawn EPERM`.
  RSpec no ejecutado localmente según el brief. Smoke con Meta y revisión visual
  móvil/escritorio en claro/oscuro pendientes. Sin migraciones ni commit.
- Verificación manual: registrar una cuenta, confirmar correo, guardar negocio
  sin web, recargar Paso 3, conectar con un número autorizado y verificar
  nombre/número antes de continuar. Repetir cancelando, simulando error y
  omitiendo; probar otra instalación sin configuración y la alternativa de canal.

#### Paso 3 — Confianza, guía de conexión y aviso móvil (ronda 5, 2026-10-17)

- En el estado inicial, bloque compacto «Tu número no se pierde» con continuidad
  de la app WhatsApp Business, conexión oficial y beneficios de la API. La frase
  «ChatHub es Meta Tech Provider» solo aparece con `metaTechProviderLive === true`.
- «Ver guía de conexión» carga bajo demanda `WhatsappGuideDialog.vue`, usando el
  diálogo existente con contenido desplazable. Explica inicio de sesión, número,
  pegar el código recibido en WhatsApp Business o escanear el QR desde otra
  pantalla y elección del historial. Incluye los límites verificados: 6 meses,
  sin grupos, mensajes temporales/visualización única, actividad de 14/30 días,
  versión 2.24.17+, 20 mensajes por segundo y ruta para desconectar la cuenta.
- Dos enlaces oficiales de Meta con `target="_blank"` y
  `rel="noopener noreferrer"`. El slot/video solo existe si se configura
  `window.chatwootConfig.whatsappGuideVideoUrl`.
- Distintivos oficiales negro/blanco copiados sin cambios a
  `app/javascript/dashboard/assets/images/meta/`; SHA-256 idéntico a los
  originales. Se muestran dentro del diálogo con la bandera activa,
  ancho de 10rem, proporción original y espacio libre de 2rem por lado.
- Ronda 7: sello también en el encabezado junto a WhatsApp, en los estados
  inicial, no disponible y conectado, solo con `metaTechProviderLive === true`.
  Negro en claro y blanco en oscuro, assets mediante `new URL` en el paso,
  ancho de 130px móvil / 150px escritorio y espacio libre de 28px por lado
  (≥ la mitad de su alto). La fila centra ambos y permite salto alineado al
  inicio si no caben. Specs cubren estados, bandera estricta y variantes de tema.
- Aviso inicial para ancho <768px o user agent móvil, con «Ingresar código»
  destacado y copia de la URL actual mediante Clipboard. Toast existente para
  éxito, permiso denegado o Clipboard ausente. El aviso queda en el contenido
  desplazable sobre el pie fijo, con tokens `n-*` para claro/oscuro.
- Configuración: `META_TECH_PROVIDER_LIVE` (texto, `'false'`) y
  `WHATSAPP_GUIDE_VIDEO_URL` (texto, `''`), sin propiedad `locked`.
  `DashboardController::GLOBAL_CONFIG_KEYS` carga ambas entradas y
  `vueapp.html.erb` publica el booleano y la URL con escape JSON.
- Archivos de esta ronda:
  - `app/controllers/dashboard_controller.rb`
  - `app/views/layouts/vueapp.html.erb`
  - `config/installation_config.yml`
  - `app/javascript/dashboard/routes/dashboard/onboarding/InboxSetup.vue`
  - `app/javascript/dashboard/routes/dashboard/onboarding/inbox-setup/WhatsappGuideDialog.vue`
  - `app/javascript/dashboard/routes/dashboard/onboarding/specs/InboxSetup.spec.js`
  - `app/javascript/dashboard/routes/dashboard/onboarding/specs/inbox-setup/WhatsappGuideDialog.spec.js`
  - `app/javascript/dashboard/i18n/locale/en/onboarding.json`
  - `app/javascript/dashboard/i18n/locale/es/onboarding.json`
  - `app/javascript/dashboard/assets/images/meta/meta_tech_provider_black.svg`
  - `app/javascript/dashboard/assets/images/meta/meta_tech_provider_white.svg`
  - `docs/BUGS.md`
- Validación: ESLint de los cuatro JS/Vue de esta ronda con 0 errores y 0
  advertencias; compilación Vue de script/template, YAML, paridad de las 142
  claves en/es y `git diff --check` correctos. Vitest onboarding/i18n: **12
  archivos, 249 pruebas aprobadas**, incluidas 58 de pantalla WhatsApp/guía
  y 110 de compilación de mensajes. El CLI habitual sigue bloqueado por
  `spawn EPERM` al arrancar esbuild; se ejecutó la API de Vitest cargando la
  configuración del proyecto en memoria, sin esbuild ni caché, resolviendo
  los enlaces de paquetes y procesando VueUse/vue-demi en Vite para compartir Vue.
- Revisión visual real móvil/escritorio y claro/oscuro pendiente: Docker no
  tiene daemon disponible y el controlador del navegador falla al iniciar por
  permisos del sandbox. Revisados los tokens y la estructura de scroll en código.
  Para verificar: abrir Paso 3 en ambos temas y móvil, abrir/cerrar la guía,
  alternar la bandera y la URL del video, copiar el enlace y comprobar el pie fijo.
  Sin migraciones ni commit.

### B-NEW-71 — Paso 4: crear, probar y activar un asistente borrador

- Alcance: onboarding versión 2. WhatsApp avanza a `assistant`; completar u omitir
  ese paso lleva al dashboard. Las cuentas anteriores conservan su recorrido.
  El paso 5 (plan) queda fuera de esta entrega. Sin migraciones ni commit.
- Captain v1 y v2 se habilitan al crear cuentas versión 2, incluso sin licencia
  pagada ni plan trial configurado. Los límites existentes del plan siguen vigentes.
- `Onboarding::CaptainDraftService` bloquea la cuenta y guarda el asistente y
  `custom_attributes.onboarding_assistant_id` en la misma transacción. Reenvíos
  reutilizan ese asistente; editar actualiza el mismo borrador y nunca sobrescribe
  uno ya vinculado. El límite de `Captain::Assistant` se aplica al crear.
- Las cuatro plantillas, tonos y reglas están centralizados en
  `enterprise/app/services/onboarding/captain_draft_templates.rb`. Componen
  instrucciones en español neutro con el objetivo del dueño y el idioma de la
  cuenta, sin generar precios ni respuestas comerciales. La composición es el
  punto de extensión documentado para futura generación IA; crear no llama al LLM.
- El borrador nace sin bandejas, citas, seguimientos ni mensajes pagados. Solo el
  botón **Activar** llama a `POST captain/assistants/:id/inboxes`. Sin WhatsApp se
  deshabilita y se ofrece volver al paso 3 manteniendo el cursor y el borrador.
  La asignación del administrador también cubre esa conexión tardía.
- El chat usa el playground existente. Para el asistente del onboarding, el
  servidor selecciona `onboarding_playground`: solo consulta de conocimiento,
  sin herramientas externas ni escenarios con acciones. El payload del borrador
  informa falta de clave/cuota; la UI permite reintentar. No se promete prueba
  gratuita ni atención real hasta activar.
- API nueva bajo el recurso autenticado de onboarding: `GET /assistant` recupera
  el borrador; `POST /assistant` recibe `name` (texto, 1–120 caracteres), `goal`
  (texto, 1–2000) y `tone` (`friendly`, `professional`, `brief`). Solo administrador;
  parámetros inválidos devuelven 422. El exceso de cupo devuelve 422 con código
  `assistant_limit`, límite y mensaje traducido. Cuenta y membresías exponen el
  ID únicamente si existe; no exponen el objetivo en el perfil.
- Frontend: `AssistantSetup.vue`, API `onboarding.js`, rutas del dashboard/guard y
  navegación mínima en `InboxSetup.vue`. Reutiliza `AuthSplitLayout`, tokens `n-*`,
  progreso «Paso 4 de 5», controles redondeados y radios nativos accesibles para
  tono. Textos completos en `locale/en/onboarding.json` y `locale/es/onboarding.json`;
  errores de servidor en `config/locales/en.yml` y `es.yml`.
- Autoevaluación: se corrigió la referencia a `STEP_INBOX_SETUP` en el módulo
  Enterprise usando la constante del controlador base; sin calificarla, el
  módulo no la resuelve y la transición puede lanzar `NameError`. Se agregaron
  request specs de transición y replay pasando por ese overlay.
- Autoevaluación: `accounts/get` devuelve el payload o `null`; el paso comprueba
  ese resultado y el booleano de `inboxes/get`, que absorben fallos HTTP. Un 5xx
  de carga ahora muestra error y reintento en vez de usar datos vacíos o viejos.
  También se permite partir nombres largos en la tarjeta del borrador en móvil.

Archivos de esta entrega:

```text
app/controllers/api/v1/accounts/onboardings_controller.rb
app/javascript/dashboard/api/onboarding.js
app/javascript/dashboard/i18n/locale/en/onboarding.json
app/javascript/dashboard/i18n/locale/es/onboarding.json
app/javascript/dashboard/routes/dashboard/dashboard.routes.js
app/javascript/dashboard/routes/dashboard/onboarding/AssistantSetup.vue
app/javascript/dashboard/routes/dashboard/onboarding/InboxSetup.vue
app/javascript/dashboard/routes/dashboard/onboarding/specs/AssistantSetup.spec.js
app/javascript/dashboard/routes/dashboard/onboarding/specs/InboxSetup.spec.js
app/javascript/dashboard/routes/dashboard/onboarding/specs/assistantGuard.spec.js
app/javascript/dashboard/routes/index.js
app/javascript/dashboard/store/modules/accounts.js
app/services/onboarding/inbox_member_assignment_service.rb
app/views/api/v1/accounts/create.json.jbuilder
app/views/api/v1/models/_account.json.jbuilder
app/views/api/v1/models/_user.json.jbuilder
config/locales/en.yml
config/locales/es.yml
config/routes.rb
docs/BUGS.md
enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb
enterprise/app/controllers/enterprise/api/v1/accounts/onboardings_controller.rb
enterprise/app/models/enterprise/account.rb
enterprise/app/services/captain/assistant/agent_runner_service.rb
enterprise/app/services/onboarding/captain_draft_service.rb
enterprise/app/services/onboarding/captain_draft_templates.rb
enterprise/app/views/api/v1/accounts/onboardings/assistant.json.jbuilder
spec/controllers/api/v1/accounts/onboardings_controller_spec.rb
spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb
spec/enterprise/controllers/api/v1/accounts/onboarding_assistants_controller_spec.rb
spec/enterprise/controllers/api/v1/accounts/onboardings_controller_spec.rb
spec/enterprise/models/account_spec.rb
spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb
spec/enterprise/services/onboarding/captain_draft_service_spec.rb
spec/services/onboarding/inbox_member_assignment_service_spec.rb
```

Cobertura:

| Spec | Qué verifica |
|---|---|
| `onboarding/specs/AssistantSetup.spec.js` | Pantalla en/es, tres ejemplos por negocio, creación/cargando/error, límite traducido sin falso éxito, edición/reanudación, respuesta de prueba, clave/cuota/error/reintento, activación explícita con/sin WhatsApp, respuesta perdida y omisión. Carga mediante la acción real de cuenta, errores absorbidos, doble activación y reintento de finalización tras 5xx. |
| `onboarding/specs/assistantGuard.spec.js` | Reanudar paso 4, volver a WhatsApp y excluir cuentas antiguas/completadas. |
| `onboarding/specs/InboxSetup.spec.js` | Continuar/omitir WhatsApp conduce al asistente, incluidas recuperación y reintentos. |
| `spec/enterprise/services/onboarding/captain_draft_service_spec.rb` | Idempotencia, cupo de un asistente, edición sin duplicar, rollback del puntero, aislamiento por cuenta, plantillas/idioma/tono, ausencia de vínculos/LLM y defaults de automatización. |
| `spec/enterprise/controllers/api/v1/accounts/onboarding_assistants_controller_spec.rb` | Crear/recuperar, validación 422, autorización, límite traducido, cuenta antigua y payload del puntero presente/ausente. Contrato de cuenta y `/auth/validate_token` usando las vistas reales, y vínculo explícito a WhatsApp. |
| `spec/enterprise/controllers/api/v1/accounts/onboardings_controller_spec.rb` | Transición a asistente a través del overlay Enterprise y replay sin mutar estado. |
| `spec/controllers/api/v1/accounts/onboardings_controller_spec.rb` | Transiciones versión 2, completar/omitir asistente, reenvíos/fuera de orden y compatibilidad legacy. |
| `spec/enterprise/models/account_spec.rb` | Ambos flags Captain en cuentas nuevas sin instalación pagada ni plan. |
| `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb` | Selección del runner restringido durante onboarding, incluso si se suministra configuración avanzada. |
| `spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb` | Prueba sin herramientas externas ni handoffs a escenarios reales. |
| `spec/services/onboarding/inbox_member_assignment_service_spec.rb` | Asignación del administrador al regresar desde el asistente a conectar WhatsApp. |
| `dashboard/i18n/messagesCompile.spec.js` | Compilación de mensajes en/es, incluidas las nuevas cadenas. |

Validación de autoevaluación: ESLint de los nueve archivos JS/Vue nuevos o modificados con **0 errores
y 0 advertencias**; paridad de las **48 claves** nuevas en/es y `git diff --check`
correctos. El CLI solicitado de Vitest falla al iniciar esbuild con **`spawn EPERM`**.
La misma selección onboarding + Captain + i18n se ejecutó mediante la API local:
**38 archivos y 445 pruebas aprobadas**, incluidas 29 de pantalla y 5 del guard nuevo.
El ejecutor temporal `tmp/run-assistant-tests.mjs` carga la configuración base en
memoria, resuelve dependencias enlazadas y omite estilos SFC en jsdom para evitar
el preprocesador Sass no disponible; no modifica configuración ni estilos de producto.
Los RSpec se escribieron y revisaron estáticamente, **sin ejecutarlos**, según el
brief; Docker Desktop tampoco dispone del daemon Linux en esta sesión. La revisión
visual en navegador y la prueba con Rails/IA/WhatsApp reales quedan pendientes;
Vitest usa respuestas simuladas y no valida la serialización real de Rails.
Detalle de cumplimiento, recorrido de datos y pendientes en
[`AUTOEVALUACION-ASISTENTE.md`](AUTOEVALUACION-ASISTENTE.md). Se usó este destino
porque los permisos de la sesión rechazan la escritura en `.codex/AUTOEVALUACION.md`.

Cómo verificar en producto: cuenta nueva → negocio → conectar u omitir WhatsApp →
asistente. Elegir ejemplo/tono y crear; recargar y comprobar que reaparece el mismo
borrador. Probar una pregunta (con IA configurada y saldo), editar y repetir. Sin
clave/saldo, comprobar mensaje y reintento. Sin WhatsApp, volver a conectarlo y
regresar sin duplicar; pulsar Activar y comprobar el vínculo. Omitir conserva el
borrador y permite entrar al dashboard. Verificar móvil y ambos temas.

### B-NEW-72 — Cupo diario de pruebas por plan y consumo del pool compartido

El playground de Captain (v1/v2) y el paso 4 del onboarding hacían llamadas a IA
sin contabilizar. Cada prueba exitosa del plan gratuito ahora consume una
respuesta del plan. Los planes de pago usan primero `Plan#captain_daily_tests`
por cuenta/día y luego el mismo pool de respuestas que los clientes reales.
No existe techo diario adicional. Los errores del modelo o la falta de clave
no consumen ni cupo ni respuestas. Las cuentas sin plan conservan el fallback
a `ChatwootApp.max_limit` y no se contabilizan (`test_usage: null`).

Migración `20261017120000_add_captain_daily_tests_to_plans`, schema y campo
editable en SuperAdmin. `plans:seed` define Prueba 0, Inicio 10, Crecimiento 20,
Negocio 35, Escala 50 y Developer 10. Tras migrar hay que aplicar esos valores a
los planes existentes mediante el seed o SuperAdmin; el default de la columna es 0.
El seed también actualiza los demás precios/límites: revisar antes de usarlo
si la instalación tiene planes personalizados.

`Captain::Playground::Usage` serializa elegibilidad/modelo/débito con el lock de
la cuenta. Redis incrementa el cupo exitoso y fija su expiración en una sola
operación Lua, a medianoche de `reporting_timezone` (UTC si no hay zona).
El contador es por cuenta/fecha, se conserva al cambiar de plan ese día y solo
cuenta pruebas cubiertas por el cupo gratuito diario. El día se fija al admitir
la solicitud. Los intentos fallidos cuentan solo para el freno móvil de 6
preguntas/minuto por cuenta, compartido entre usuarios y asistentes, con 429 y
`Retry-After`. Mensaje máximo 500 caracteres, historial máximo 10 mensajes y
4000 caracteres incluyendo la pregunta actual; se elimina lo más antiguo.

BYOK confirmado: `Integrations::Hook` OpenAI habilitado guarda `settings.api_key`;
`lib/captain/base_task_service.rb` ya lee ese campo para tareas compatibles.
El historial BYOK contiene `45f4b423ae` y `b67ba61bda`. No se inventó una columna:
`Account#own_ai_key_configured?` comprueba esa integración real. Las pruebas con
clave propia no consumen ningún pool/cupo. Developer sin clave se comporta como
plan de pago normal y, con su pool mensual 0, se detiene al terminar el cupo diario.
El controlador aplica `Llm::Config.with_chat_context` únicamente al playground:
usa un contexto RubyLLM aislado de la solicitud, sin endpoint de la instalación,
para los constructores de chat de v1 y ai-agents v2 (incluidos handoffs/rewrites).
El contexto se restaura en `ensure`; las claves globales no se modifican. Esta
adaptación es necesaria porque ai-agents 0.12 construye RubyLLM::Chat directamente
sin aceptar contexto; evita depender de una clave global para construir el chat.

La API devuelve `test_usage` con tipo de plan, cupo total/usado/restante, origen
del próximo consumo y respuestas del plan restantes. `GET playground_usage`
permite avisar antes de la primera pregunta; POST y errores de cuota/ritmo
actualizan el mismo estado local de ambas pantallas. El agotamiento del pool
responde 422 `responses_limit_reached` antes del modelo, traducido en/es, con
enlace a planes. El guard permite abrir facturación desde el paso 4 sin finalizarlo.
No se modifica `ResponseBuilderJob` ni la contabilización de clientes reales.

Cobertura: RSpec de Usage/Input, contratos v1/v2/onboarding, modelos Plan/Account,
contexto BYOK y regresión del job. Vitest cubre los cinco estados de consumo,
precarga de saldos, traducciones, reintento y acceso a planes. Resultados y
limitaciones exactos en `tmp/AUTOEVALUACION-TOPES.md`.

Cómo probar: en Prueba, cada éxito baja 1 del pool. En Inicio, las primeras 10
pruebas del día no lo cambian; la siguiente sí consume. Con ambos saldos a 0,
comprobar 422 sin llamada a IA. Siete solicitudes válidas en 60 segundos entre
usuarios de la misma cuenta deben dar 429 y permitir reintentar después.
Repetir en ambos chats y v1/v2, dos pestañas, medianoche, cambio de plan, error
sin consumo y Developer con/sin hook OpenAI. Aplicar migración antes del deploy.

### B-NEW-73 — Icono de Captain y sin foto en el paso 4

El paso de onboarding configura el asistente con el icono de marca de Captain
en su encabezado y el título «Configura tu primer asistente» (en: «Set up your
first assistant»). El icono usa `i-woot-captain`, mide 40 px y es decorativo.
Se eliminó del recorrido el bloque de foto, el avatar de la tarjeta del borrador
y las imágenes en las burbujas de prueba; estas muestran el nombre del asistente.

Archivos: `onboarding/AssistantSetup.vue`,
`onboarding/specs/AssistantSetup.spec.js` y `locale/{en,es}/onboarding.json`.
El onboarding ya no usa ni modifica los endpoints o el backend de avatar. La
configuración de avatar del panel de Captain sigue funcionando sin cambios.

Cobertura: Vitest verifica el icono decorativo y el título en inglés y español;
la vista no renderiza campos de archivo ni imágenes de avatar. Autoevaluación y
límites de verificación: `tmp/AUTOEVALUACION-ICONO.md`.

Cómo probar: abrir el paso 4 en ambos idiomas, comprobar el icono Captain en el
encabezado, editar el borrador y enviar preguntas de prueba; en la tarjeta y en
las burbujas solo debe aparecer el nombre del asistente, sin fotos.

### B-NEW-075 — CI del playground: ejecutar Lua con Redis real y corregir setup del paso 4

- **Causa:** `MockRedis` no ejecuta Lua; las llamadas nuevas a `eval` fallan con `TypeError: wrong argument type Hash (expected binding)` antes de generar respuestas. Además, el spec de finalización del onboarding intentaba crear el borrador desde `inbox_setup`, aunque el servicio exige el paso `assistant`.
- **Archivos:** `spec/support/real_redis.rb`, specs de cuotas y uso del playground, contexto playground de `assistants_controller_spec.rb` y `onboarding_assistants_controller_spec.rb`.
- **Fix:** optar esos ejemplos a Redis real con namespace único por ejemplo y limpieza limitada a ese namespace; conservar el MockRedis del resto de la suite. Verificar el timestamp de expiración y el cambio de fecha sin depender del reloj real de Redis durante `travel_to`. Crear el borrador desde el paso elegible y verificar el éxito antes de leer su ID.
- **Cómo probar:** CI EE con Redis disponible; ejecutar los specs de playground y onboarding, incluyendo rate limit, allowance diario, pool compartido y errores del modelo. RSpec no disponible localmente; diagnóstico basado en el run `39153664286` y comparación con develop `39153434965` (cero fallos).

### B-NEW-074 — Revisión visual del paso 4 y botones de marca

El icono Captain conserva el slot `#brand` compartido con el logo del paso 3:
28 px en móvil y 40 px desde `sm`, con `text-n-slate-12` para ambos temas.
Se descarta la variante local `title-icon` porque cambiaba la posición del icono.
`AuthButton.vue` usa ahora `bg-n-brand` y texto blanco para las acciones primarias
del recorrido, incluida «Activar»; las secundarias conservan su borde.
`tailwind.config.js` incluye los tokens JavaScript de Auth en el escaneo para
generar también las clases de campos y enlaces compartidos de `authStyles.js`.

Archivos: `onboarding/AssistantSetup.vue`, `Auth/AuthButton.vue`,
`tailwind.config.js` y las expectativas existentes de los specs del paso y Auth.
El pie ya reserva su altura real fuera del contenedor con scroll; no requiere
cambios. El campo de pregunta pasa a 80 px en móvil para mostrar las dos líneas
del texto de ayuda; mantiene 56 px desde `sm`. No se modifica la configuración
de avatar de Captain.

Cómo probar: abrir formulario, borrador, chat y reanudación del paso 4 en claro
y oscuro, a 1280, 360, 390 y 430 px. Desplazar el contenedor hasta el final:
deben verse las tres opciones de tono o el área de chat, sin solaparse con el
pie. Comprobar el icono en la misma fila de marca que el paso 3 y las acciones
primarias azules. Evidencia y límites: `tmp/REVISION-PASO4.md`.

### B-NEW-082 - PR #182 backend CI: import diagnostics and Flow contracts

- Files: `app/services/variables/import_diagnostics.rb`, `config/locales/{en,es}.yml`, `app/jobs/flows/deferred_send_job.rb`, `spec/services/flows/action_service_spec.rb`.
- Cause: I18n treats `scope` as a lookup option, producing `contact.variables.import_undefined`; the deferred job renders the content/buttons envelope under another `content` root; the action spec inherits a numeric attribute from its factory while writing `stored`.
- Fix: rename the interpolation argument/placeholder to `attribute_scope` (including the existing Spanish placeholder, without changing translated copy); render each deferred payload field at its own root; explicitly define the spec attribute as text. Preserve the `result:` keyword and all expectations.
- Verify: CI-image RuboCop inspected all three changed Ruby files with zero offenses; standalone I18n interpolation passed in en/es. Statically traced both import callers, Flow context propagation, typed normalization and skipped-send advancement. RSpec is deferred to CI as required by the task.

## 8. Docs relacionadas

- [`INTERNAL_TASKS_AND_ALERTS.md`](INTERNAL_TASKS_AND_ALERTS.md)
- [`AGENTS.md`](../AGENTS.md)

### B-NEW-076 ? Onboarding country detection and deterministic CI

- Files: `onboarding/specs/Index.spec.js`, `specs/account-details/useAccountEnrichment.spec.js`, `account-details/useAccountEnrichment.js`.
- Fix: pin browser timezone, supported zones and language in business specs; restore spies after each test. Pin the enrichment suite language too. UTC does not identify a country, so use saved country preferences or expose the country selector instead of inferring US from en-US.
- Verify: run the PR frontend specs with TZ=UTC and TZ=America/Guayaquil, LANG=en_US.UTF-8. Cover UTC with and without saved preferences; retain UTC as the reported timezone when none is saved.

### B-NEW-077 — Onboarding header logo and visual preset

- Files: `onboarding/shared/OnboardingShell.vue`, `onboarding/specs/Index.spec.js`.
- Fix: preserve the same globalConfig logo/logoDark sources as login; use the shipped light/dark brand assets when a source is missing or fails. Reserve a fixed height, preserve aspect ratio and prevent flex shrinking. Visual presets must supply the real ChatHub logos.
- Verify: force a configured logo load error, inspect both fallback paths, and capture business, WhatsApp, assistant, plan, mobile and dark views with real brand assets.

### B-NEW-078 — Plan comparison surfaces and absent Captain usage

- Files: `components-next/plans/PlanCompareButton.vue`, `captain/pageComponents/overview/v2/UsageCard.vue`, `captain/pageComponents/{response,document}/LimitBanner.vue`, paywalls and en/es locales.
- Fix: open the shared catalog from ChatHub usage and limit notices; retain administrator restrictions and provider billing. Show missing usage as unavailable instead of zero, highlight catalog features, remove legacy tier claims and the unused trial countdown copy. Use amber-12 for AA text contrast in ChatHub limit banners.
- Verify: run `components-next/plans/specs/surfaces.spec.js` in UTC and America/Guayaquil. Compare missing and genuine zero usage; open comparison from usage, paywall and banners; verify agents cannot load it and Cloud/Shopify retain billing. Review `plan6-*` screenshots at 390 px and in both themes.

### B-NEW-080 - Text editors share the server variable catalog (MV-07/08/09)

- Files: `components-next/variable-picker/VariablePicker.vue`, shared `InsertVariableButton.vue`, `conversation/VariableList.vue`, `WootWriter/Editor.vue`, canned Add/Edit, automation text/attribute actions and `LiveChatCampaignForm.vue`.
- Fix: use the catalog by surface and capability; insert server expressions for literal Unicode, dot and hyphen keys. Attribute targets honor `managedBy` and automation write capability; unavailable saved targets stay visible and read only. Keep company and Flow groups separate. Remove the unused legacy builder, MESSAGE_VARIABLES and duplicate canned picker.
- Interaction fixes: insert at the editor selection, preserve text after the caret trigger, restore focus on selection/Escape, prevent retry from submitting a canned form, scope campaign insertion to its own editor, bound menus to the canned modal and allow the automation toolbar to wrap on mobile. Picker group/placeholder text uses slate-11 for AA contrast.
- Verify: `components-next/variable-picker/specs/VariableEditors.spec.js` mounts real editors in Add/Edit canned, automation, MacroNode and live campaign, with keyboard, caret, failure/retry, loading/empty, literal attribute and managed-destination cases. Run the scoped frontend suite in UTC and America/Guayaquil; inspect `motor4-*` captures in both themes at 1280/390 px. No backend, sending or migration changes.

### B-NEW-081 - Widget variable validation before contact initialization (PR #181)

- Files: `app/controllers/api/v1/widget/contacts_controller.rb`, `spec/requests/variables_write_contract_spec.rb`.
- Cause: `WebsiteTokenHelper#set_web_widget` calls `permitted_params` before `set_contact`. Validating variables inside parameter filtering dereferenced a nil contact and returned 500 before the writer could report read-only data.
- Fix: validate raw custom attributes in an update/set_user callback after widget/contact initialization, before identity changes or writes. Keep the existing ParameterMissing handler and its 422 error message.
- Verify: the existing prechat request spec rejects `total_citas`, checks the read-only error message and preserves the stored value. Review set_user ordering and malformed input before strong parameter filtering. RSpec runs only in CI; local CI-image RuboCop passed on all four changed Ruby files.
- Related CI expectations: ContactDrop intentionally capitalizes names (MV-02). The Captain spec now asserts the full literal `{{ Date.today }}` output; the multi_list spec uses the unformatted contact identifier to assert exact `VIP` preservation without changing the established name contract.

### B-NEW-196 — Orden determinista entre reglas de automatización (2026-10-23)

- Archivos: `app/models/automation_rule.rb`, `app/listeners/automation_rule_listener.rb`,
  `app/jobs/automations/time_based_scheduler_job.rb`, `app/jobs/automation_rules/trigger_pending_executions_job.rb`
  y `app/services/automation_rules/{simulation_service,cross_rule_linter}.rb`.
- Causa: listener y simulación dependían del orden de PostgreSQL, sin `ORDER BY` explícito.
- Arreglo: un único scope `in_execution_order` por ID ascendente para eventos, simulación, scheduler temporal/contacto
  y encolado de esperas. La creación combina sus reglas con las de actualización con espera antes de ordenar;
  la simulación comparte esa selección y numera coincidencias consecutivas. El barrido conserva candidatos y límite
  por vencimiento antes de ordenar. Los jobs de espera siguen siendo independientes: su finalización concurrente no se serializa.
- Verificación: specs de los cinco eventos con tres IDs insertados fuera de orden y asignaciones en conflicto repetidas;
  simulación con filtros, reglas diferidas y numeración; scheduler mixto temporal/contacto; barrido con límite.
  Revisión estática y `git diff --check`; RSpec y RuboCop pendientes del PM en Docker según el brief.
- Sin migraciones, frontend ni cambios en las condiciones de elegibilidad del motor. Informe local: `tmp/PR-ORDEN.md`.

### B-NEW-197 — Posponer automatizaciones con duración (2026-10-23)

- Archivos: `app/services/action_service.rb`, `app/services/conversations/snooze_parameters.rb`
  y `app/services/automation_rules/action_validation_service.rb`.
- Causa: `snooze_conversation` ignoraba parámetros y no establecía una fecha de reapertura.
- Arreglo: duración entera positiva en minutos, horas o días, hasta el equivalente a 365 días;
  hash directo o primer elemento de una lista. Validación compartida al guardar reglas y al ejecutar.
  Sin parámetros se conserva la transición anterior; parámetros inválidos en ejecución dejan la
  conversación pospuesta sin fecha y registran el error con el id de la regla y la conversación.
  Macros y flujos heredan el comportamiento. El callback, el job de reapertura y la actividad existente se conservan.
- Verificación: specs de `AutomationRules::ActionValidationService`, `AutomationRules::ActionService`,
  `Macros::ExecutionService`, `Flows::ActionService` y `Conversations::ReopenSnoozedConversationsJob`.
  Incluyen límites equivalentes por unidad, compatibilidad, `travel_to`, fallback y reapertura al vencer.
  Revisión estática y `git diff --check`; RSpec y RuboCop pendientes del PM en Docker según el brief.
  Sin migraciones ni cambios de frontend o i18n.



### B-NEW-233 — Restaurar el orden original de Enviar por WhatsApp (2026-10-24)

- Archivos: `components-next/whatsapp/send-center/SendCenter.vue`, `WhatsAppTemplateParser.vue` y sus specs.
- Causa: el primer arreglo de PR #223 intercambió variables y vista previa respecto de `1ebdc02bc2^`.
- Arreglo: restaurar lista → vista previa → variables a 1280 px, con anchos y separación originales; usar `data-template-fields` para ubicar el formulario sin depender de hijos ordinales. Mantener una columna en m?vil y los mensajes de error dentro del formulario. Quitar el texto visible de zona horaria y su estado local sin modificar la resoluci?n de Rails; conservar la clave i18n existente.
- Verificación: specs de ambos parsers reales en SendCenter; el parser oculta UTC y America/Guayaquil y conserva valores/payload. Comparar capturas `fixenvio2-original-*` / `fixenvio2-despues-*` en 1280x900 y 390x844. El original m?vil ya desbordaba; la versi?n corregida conserva lista, preview y variables visibles, sin scroll horizontal.

### B-NEW-232 — Insertar variables dentro del campo de plantilla (2026-10-24)

- Archivos: `components-next/variable/TemplateVariableInput.vue`, `whatsapp/WhatsAppTemplateParser.vue`, `content-templates/ContentTemplateParser.vue` y specs correspondientes.
- Causa: el selector separado reducía el ancho disponible para escribir valores en la tercera columna de Enviar por WhatsApp; Twilio no ofrecía el mismo patrón.
- Arreglo: reutilizar Input y VariablePicker en modo insert con icono de llaves dentro del campo, a la derecha, etiqueta accesible y tooltip «Insertar variable». Reservar padding lógico y mínimos de altura para resistir los estilos compactos de SendCenter. Objetivo de 40 px en escritorio y 44 px en móvil. Header y cuerpo de Meta y cuerpo de Twilio comparten la pieza; los consumidores heredan el cambio. Catálogo, filtros, validaciones y contratos de envío conservados.
- Verificación: integración con ambos parsers reales para editar, abrir el picker con el icono, insertar en el campo elegido y enviar el payload esperado; suites de consumidores y compilación i18n en UTC y America/Guayaquil. Capturas `fixenvio3-*` de reposo, picker, texto largo, dos variables, oscuro y Twilio a 1280x900 y 390x844; geometría sin scroll horizontal.

### B-NEW-239 — Hacer persistentes y accesibles los errores de carga (2026-10-24)

- Archivos: `components-next/LoadErrorNotice.vue`, `InternalTasks/TaskKanban.vue`, `settings/templates/flows/FlowsPanel.vue`, `companies/pages/CompaniesIndex.vue` y `components/SnackbarContainer.vue`.
- Causa: un fallo de primera carga parecía una lista vacía y los fallos al refrescar no explicaban que los datos mostrados podían estar desactualizados.
- Arreglo: aviso compartido con reintento manual, estados normal/compact, preservación de datos y filtros en los pilotos Tareas, Flujos y Empresas; contenedores y skeletons anuncian estado de carga accesiblemente; los toasts usan región polite.
- Verificación: `LoadErrorNotice.spec.js` (2 casos), `SnackbarContainer.spec.js` (1 caso), `FlowsPanel.spec.js` (20 casos; incluye rechazo y retry exitoso). Suite amplia UTC: 196 suites pasaron, 2 fallaron y 1 se omitió (2088 tests pasaron, 4 fallaron, 2 omitidos); suite America/Guayaquil: 197 suites pasaron, 1 falló y 1 se omitió (2090 tests pasaron, 2 fallaron, 2 omitidos). Los dos fallos persistentes son `ShopifyBilling.spec.js`, ajenos al cambio. Capturas pareadas pendientes: no se encontró Playwright/CDP utilizable en el entorno.
