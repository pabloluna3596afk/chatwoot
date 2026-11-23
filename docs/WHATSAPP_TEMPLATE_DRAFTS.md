# Borradores de plantillas de WhatsApp: contrato backend

Base: `/api/v1/accounts/:account_id/whatsapp_template_drafts`. Todas las operaciones,
incluidas lista, detalle y archivo de ejemplo, requieren un administrador de la cuenta.
La migración `20261120120000` debe aplicarse antes de habilitar estas rutas.

Guardar nunca contacta a Meta. Las plantillas instaladas y sus bindings siguen usando
las APIs anteriores. Un borrador no es una plantilla enviable.

## Rutas

| Método y ruta relativa | Entrada | Respuesta |
| --- | --- | --- |
| `GET /` | Query `page`, `per_page`: cadenas decimales positivas; máximo 100 por página | `200`, `payload` de borradores activos y `meta` con total/página/tamaño |
| `POST /` | `{ "draft": { ... } }` | `201`, detalle local |
| `GET /:id` | — | `200`, detalle, incluso archivado |
| `PATCH /:id` | `{ "draft": { "lock_version": 0, ... } }` | `200`, detalle con nueva revisión |
| `DELETE /:id` | `{ "lock_version": 0 }` | `204`; si tiene historial o copias, conserva el registro archivado |
| `POST /:id/archive` | `{ "lock_version": 0 }` | `200`, detalle archivado |
| `POST /:id/duplicate` | `{ "destination": { "preferred_channel_id": 12, "waba_id": "123" } }` | `201`, copia independiente con nombre sugerido distinto |
| `POST /new_version` | `{ "channel_id": 12, "remote_id": "456" }` | `201`, copia local de una plantilla del espejo remoto, con otro nombre |
| `POST /:id/media` | Multipart: `file`, `lock_version` como **cadena decimal** | `200`, detalle con archivo local y nueva revisión |
| `GET /:id/media` | — | Archivo adjunto; requiere la misma autenticación de administrador |
| `DELETE /:id/media` | JSON `{ "lock_version": 1 }` | `200`, detalle sin archivo |
| `POST /:id/submit` | JSON `{ "lock_version": 2 }` | `202`, intento persistido; después se procesa en background |
| `POST /:id/submissions/:submission_id/reconcile` | — | `202`, intento y comprobación encolada; respeta el backoff pendiente |

Los IDs numéricos del JSON son enteros; `waba_id` y los IDs de Meta son cadenas.
La única revisión que se envía como cadena es la del formulario multipart.
No se aceptan signed IDs de blobs del cliente para adjuntar archivos ajenos.

## Contenido editable

```json
{
  "draft": {
    "title": "Confirmación de cita",
    "name": "cita_confirmacion_v2",
    "language": "es",
    "category": "UTILITY",
    "parameter_format": "NAMED",
    "waba_id": "123",
    "preferred_channel_id": 12,
    "definition": {
      "header": { "format": "TEXT", "text": "Tu cita" },
      "body": { "text": "Hola {{nombre}}, tu cita está confirmada.", "examples": ["Ana"] },
      "footer": { "text": "Gracias" },
      "buttons": [{ "type": "QUICK_REPLY", "text": "Confirmar" }]
    },
    "variable_bindings": { "nombre": "contact.name" }
  }
}
```

También es válido guardar `{ "draft": { "definition": {} } }`. Nombre, idioma,
categoría y destino pueden faltar o ser `null`; el título predeterminado es vacío.
Los campos presentes conservan su tipo. Se comprueban tamaños, forma del JSON,
pertenencia y archivo al guardar. No se comprueba la credencial contra Meta.

`definition` usa el formato del builder existente: `header`, `body`, `footer`,
`buttons` y opcionalmente `preserved`. Los ejemplos son arrays de cadenas. Botones:
`QUICK_REPLY`, `URL` (`url`, `examples`), `PHONE_NUMBER` (`phone_number`),
`COPY_CODE` (`code`, solo marketing). Los encabezados de media usan IMAGE, VIDEO o
DOCUMENT y un archivo local; el cliente no proporciona un handle remoto.

El JSON tiene límite de 1 MiB. Texto: cuerpo 1024, encabezado/pie 60, etiqueta de
botón 25; URL 2000, teléfono 20 y cupón 15. Se permiten contenidos incompletos,
pero enviar exige el contrato completo del builder, ejemplos, catálogo de idiomas,
grupos de botones correctos y archivo compatible. Los parámetros nombrados nuevos
usan letras minúsculas y guion bajo. AUTHENTICATION y componentes externos opacos
no se convierten a una creación genérica. Se conservan localmente y se bloquea su
envío desde este editor, sin modificar el recurso instalado.

Copiar conserva el archivo local y elimina referencias/handles remotos de la
definición, incluso anidados. `source_remote_id` y `source_draft_id` son trazabilidad
del servidor. La nueva versión se copia del caché remoto existente, sin GET a Meta.

## Revisiones, estados y recuperación

`lock_version` controla ediciones concurrentes y es la revisión del intento. PATCH,
archivo y cambios de media devuelven la revisión actualizada. Un doble clic sobre
la misma revisión devuelve el mismo intento, también si ya falló. Para corregir un
fallo definitivo primero hay que guardar una revisión nueva.

El detalle devuelve campos por lista permitida, autores, fechas, metadatos del
archivo, `submissions` y `status`. Este último corresponde al intento de la revisión
actual; si esa revisión no tiene intento, es `draft`. Intentos anteriores siguen
disponibles en `submissions`. El POST de envío devuelve el intento, no el borrador.
Se consulta el detalle para seguir el procesamiento.

Estados locales: `draft`, `submitting`, `submitted`, `failed`, `reconciling`.
`remote_status` es nullable y conserva el valor real, incluso valores nuevos de
Meta. `submitted` acredita el alta remota; no acredita aprobación ni entrega.
`remote_category` es la categoría real, que puede diferir de la solicitada.

El intento contiene un snapshot inmutable, referencia al archivo y payload de
solicitud de escritura única. Nunca contiene credenciales. Un lock PostgreSQL por
intento serializa workers; un índice único protege cuenta+WABA+nombre+idioma entre
borradores distintos. Cambiar el borrador mientras se procesa no cambia el envío.
Otro número de la misma WABA puede aportar credenciales; otra WABA nunca se utiliza.

Antes del primer POST se consulta la identidad remota. Un homónimo existente exige
otro nombre; no se adopta ni se sobrescribe. Un timeout pasa a `reconciling` y solo
se consulta la identidad. Si coincide el contenido, se registra el éxito; si falta
o es ambiguo, no se repite el POST. La media requiere coincidencia del handle;
si Meta no lo devuelve, la comprobación permanece ambigua.

429/5xx permiten hasta tres ejecuciones, con esperas de 30 s y 120 s y consulta
previa de identidad. Al agotar el límite queda en reconciliación manual. Errores
definitivos de validación o token fallan sin reintento automático. Tras rechazo
remoto se puede crear una nueva versión con nombre distinto; este flujo no edita
una identidad ya instalada. La comprobación manual de un intento `submitted`
refresca estado, categoría y motivo desde Meta.

El éxito encola una sincronización separada de todos los canales propios de esa
WABA. Un fallo de sincronización no cambia un alta exitosa a fallida. La lectura de
esa sincronización es completa: admite lista vacía y no aplica páginas parciales.

Guardar, archivar o eliminar localmente no cambia Meta ni bindings activos. Los
bindings del borrador quedan como preparación local; su activación continúa siendo
explícita mediante el recorrido existente de plantillas instaladas. No hay backfill,
migración de consumidores, webhook nuevo ni cambio del consumo de plantillas instaladas o Citas.
Captain conserva su exclusión de marketing, incluso si Meta recategoriza una alta.

## Errores

- `401`: usuario sin rol administrador; `404`: recurso fuera de la cuenta o ausente.
- `422 invalid_draft`: forma, tamaño, destino o validación local; `details` identifica campos.
- `422` con código del builder: contenido aún incompleto o incompatible para envío.
- `409 stale_revision`: recargar y resolver la edición concurrente.
- `409 identity_conflict`: una carrera chocó con la reserva de identidad. Una colisión
  detectada antes por validación del modelo devuelve `422`.
- Los fallos del worker se consultan en `submissions[].error_details`; incluyen código
  y detalle Meta sanitizado, sin credenciales ni ejemplos reflejados por Meta.

El listado y el serializador no exponen snapshots, payloads con handles ni configuración
del proveedor. Las APIs antiguas de crear/editar/eliminar plantillas siguen disponibles.

## Crear desde blueprints y biblioteca

Los endpoints legados de creación directa permanecen disponibles sin cambios.
Las rutas nuevas siguientes son exclusivas de administradores y devuelven `201`
con el mismo detalle de borrador; guardar no escribe ni consulta Meta.

Ambas rutas aceptan JSON plano (sin envolverlo en `draft`). Una respuesta de
`/from_library`, por ejemplo, contiene estos campos del detalle común:

```json
{
  "id": 31,
  "title": "",
  "name": "mi_recordatorio",
  "language": "es",
  "category": "UTILITY",
  "parameter_format": "POSITIONAL",
  "preferred_channel_id": 12,
  "waba_id": "123",
  "definition": {
    "library": {
      "template_name": "appointment_reminder",
      "language": "es",
      "button_inputs": []
    }
  },
  "lock_version": 0,
  "status": "draft",
  "submissions": []
}
```

Es un extracto: la respuesta también incluye los demás campos del serializador
común, como autores, fechas y media. `/from_blueprint` devuelve la misma estructura
con `definition.body` (texto y ejemplos) y `definition.buttons` de respuesta rápida,
en lugar de `definition.library`.

Errores de estas dos rutas:

- `422 invalid_draft`: tipos JSON incorrectos, definición inválida o conflicto
  detectado por validación local. La respuesta contiene `error` y `message` o
  `details`, según la validación.
- `422 unknown_blueprint`: `blueprint_id` no existe; `422 cloud_channel_required`:
  el canal propio no es WhatsApp Cloud.
- `/from_library` también devuelve `422 library_name_required`, `invalid_name`,
  `invalid_language` o `invalid_category` para identidades inválidas.
- Permisos (`403`): **estas rutas no emiten `403` actualmente**. El guard compartido
  `check_admin_authorization?` y `RequestExceptionHandler` responden `401` con
  `{ "error": "You are not authorized to do this action" }` para un agente.
  Se conserva este contrato existente; un canal ajeno o inexistente devuelve `404`.

| Ruta POST relativa | Entrada JSON |
| --- | --- |
| `/from_blueprint` | `{ "blueprint_id": "palu_cita_confirmacion", "channel_id": 12 }` |
| `/from_library` | `{ "library_template_name": "appointment_reminder", "name": "mi_recordatorio", "language": "es", "category": "UTILITY", "button_inputs": [], "channel_id": 12 }` |

`channel_id` es opcional y debe ser un entero de un canal WhatsApp Cloud de la
cuenta. Un canal ajeno devuelve `404`; un proveedor incompatible, `422`.
Sin canal se puede guardar y duplicar; enviar exige destino.

Blueprints permitidos: `palu_reenganche`, `palu_cita_confirmacion` y
`palu_cita_recordatorio`. Leen las constantes del servicio legado y producen
cuerpo, ejemplos y botones `QUICK_REPLY` equivalentes, idioma `es` y formato
`POSITIONAL`. Si el nombre ya está activo en cuenta/WABA/idioma o en el espejo
remoto de esa WABA, se prueba `_2`, `_3`, etc. Un ID desconocido devuelve
`422 unknown_blueprint`. No se añade una pantalla para blueprints.

Un borrador de biblioteca conserva exclusivamente este modo en `definition`:

```json
{
  "library": {
    "template_name": "appointment_reminder",
    "language": "es",
    "button_inputs": [{ "type": "PHONE_NUMBER", "phone_number": "" }],
    "preview": {
      "body": "Texto de Meta",
      "buttons": [{ "type": "PHONE_NUMBER", "text": "Llamar" }]
    }
  }
}
```

No admite `body`, `header`, `footer`, `buttons` o `preserved` editables al mismo
nivel. `preview` es opcional, de solo presentación: `header`/`body` son cadenas
hasta 1024 caracteres y `buttons` usa los límites del JSON del editor. También
puede proporcionarse como `preview` en `/from_library`. No se confía en esta vista
previa para crear ni reconciliar una plantilla.

`template_name` es cadena hasta 512 caracteres; `language`, hasta 20. Los inputs
son un array de hasta 10 objetos, en el orden de los botones URL/PHONE_NUMBER de
Meta. PHONE_NUMBER admite solo `type` y `phone_number` (hasta 20 caracteres). URL
admite `type` y `url: { base_url, url_suffix_example }`, cadenas hasta 2000
caracteres; el ejemplo de sufijo es opcional al guardar. Se permiten valores
vacíos para completar luego. Tipos incorrectos, campos desconocidos, tamaños o
mezcla de modos devuelven `422 invalid_draft`. Los borradores antiguos sin
`library`, incluido `definition: {}`, mantienen su contrato.

`/from_library` exige el nombre de biblioteca y nombre/idioma/categoría con las
mismas reglas de identidad del endpoint legado (`library_name_required`,
`invalid_name`, `invalid_language`, `invalid_category`). Un homónimo local activo
se rechaza por la validación existente; el administrador puede elegir otro nombre.

PATCH conserva el formato de revisión existente y permite completar identidad e
inputs. Para biblioteca, el editor toma el idioma de `definition.library.language`
y no permite cambiarlo conservando la vista previa anterior. Crear o editar por
API con un idioma efectivo distinto devuelve `422 invalid_draft`, incluso si el
PATCH solo contiene `language`. La comparación respeta la normalización regional
existente (`es_EC` equivale a `es`; `en_US` se conserva). Para elegir otro idioma
hay que elegir una definición de biblioteca y vista previa correspondientes.
Al enviar se valida el catálogo de idiomas y el destino y se consulta la
biblioteca mediante el cliente común, con paginación. El texto y los botones se
resuelven en el idioma solicitado; un fallback distinto no se envía silenciosamente.
Se exige un input por botón URL/PHONE_NUMBER, tipo y orden correctos, teléfono
válido, URL HTTP(S) y ejemplo cuando el botón tiene sufijo dinámico. Errores de
inputs devuelven `422 invalid_buttons`; una plantilla no disponible en ese idioma,
`422 invalid_language`. Ningún intento se reserva si esta validación falla.

El cliente existente normaliza idiomas regionales de biblioteca (`es_EC` → `es`,
conserva `en_US`/`pt_BR`). El snapshot y la identidad reservada del intento usan el
idioma efectivo, para que búsqueda previa, POST y reconciliación coincidan. El
borrador conserva la selección del usuario. El snapshot congela inputs y texto
obtenido de Meta, sin credenciales. El worker usa `create_from_library`, que envía
`library_template_name` y `library_template_button_inputs`; se mantienen la misma
idempotencia por revisión, bloqueo, backoff y reconciliación. Si el contenido
remoto no coincide, no se adopta como éxito ni se repite el POST tras timeout.

Duplicar conserva `library` y crea un nombre independiente sin intentos ni IDs
remotos en la definición. Nueva versión de una plantilla creada por este camino
recupera el modo desde el snapshot de su intento, por cuenta/WABA/ID remoto;
conserva `source_remote_id` solo como trazabilidad. Las versiones de plantillas
sin snapshot de biblioteca conservan el recorrido previo desde el espejo remoto.
No hay migración nueva, backfill ni cambios de campañas, chat o Citas.

## Recursos de Citas

La migración aditiva y reversible `20261122120000` incorpora
`calendar_template_resources`. Aplicarla antes de servir consumidores de Citas
y bandejas. No requiere backfill. Regenerar el schema desde la base de pruebas
migrada, según `docs/TESTING.md`; no editarlo a mano.

Cada identidad es cuenta + función (`confirmation`, `cancellation`, `reminder`)
e idioma (`es`/`en`) + WABA. Un índice parcial adicional protege la identidad
sin WABA. Dos números de una misma WABA comparten el recurso; otra WABA tiene
su propia selección. `Calendar::TemplateDefinitions` contiene nombres, textos,
variables y botones; `ActivationKit` conserva sus constantes públicas y su
transporte legado. Este cambio no prepara borradores al conectar Google ni
enciende recordatorios, crea plantillas remotas o modifica `palu_*`.

API interna: `Calendar::TemplateResources.new(account:, function:, language:,
channel: nil)`. `prepare!` crea una identidad pendiente una sola vez, incluso
sin canal, y conserva cualquier selección existente. `link!(template_name:,
remote_template_id:, draft: nil)` requiere un canal Cloud propio con WABA y
una selección explícita de nombre **e ID remoto** desde su espejo sincronizado.
El borrador es opcional y debe pertenecer a esa cuenta y destino. No hay
endpoint ni adopción automática por nombre en este PR.

Vincular requiere `APPROVED`, categoría `UTILITY`, idioma exacto, formato `NAMED`,
las cuatro variables del cuerpo (`nombre`, `cita`, `fecha`, `hora`) y botones
`QUICK_REPLY` Confirmar/Reagendar/Cancelar (o sus etiquetas inglesas) en ese orden.
Cancelación no lleva botones. Se permiten cambios de texto, encabezado de texto
y pie estáticos; se rechazan variables adicionales, media y acciones desconocidas.
Un contrato inválido queda `incompatible` con `incompatibility_reason`.

`resolve` devuelve la plantilla del recurso vinculado o `nil`. Comprueba el
contrato actual y el digest SHA-256 del contenido remoto elegido; cambios de
categoría, estado, identidad o contenido invalidan el vínculo. Restaurar el
contenido requiere vinculación explícita; no cambia de versión silenciosamente.
El snapshot incluye variables, mapa etiqueta→acción y versión. La revisión local
opcional `draft_revision_at_link` es trazabilidad del borrador al vincular, no
prueba de que esa revisión local fue enviada o aprobada.

Preparación y vinculación bloquean primero la cuenta y después la fila del recurso.
La cuenta serializa también la primera creación sin WABA; los índices únicos
protegen escritores concurrentes. `RecordNotUnique` se recupera fuera del savepoint
fallido, con otro bloqueo y lectura de la fila ganadora. Resolver bloquea la fila
al comprobar/inutilizar una versión. No se hacen llamadas a Meta.

Si no hay versión vinculada (recurso ausente o solo pendiente de preparación), la compatibilidad busca los nombres
fijos `cita_confirmacion`, `cita_cancelacion`, `cita_recordatorio` ya instalados,
también exigiendo `UTILITY` + `APPROVED` e idioma exacto. No exige retrospectivamente
un snapshot ni reconstruye el contrato de estas instalaciones antiguas. Un recurso
incompatible bloquea ese fallback en su destino: una selección explícita fallida no
se sustituye silenciosamente por otra plantilla.

CustomerNotice y recordatorios resuelven por función. El mensaje conserva
`calendar_event_id`, `template_params` y valores resueltos; añade
`content_attributes.calendar_template_resource` con recurso (nullable en legado),
versión, WABA, ID/nombre remotos, variables y acciones. Los botones usan el snapshot
enviado aunque el recurso se sustituya o elimine. Los mensajes sin snapshot siguen
reconociéndose por nombres y etiquetas fijos antiguos. La entrega de recordatorios
revalida la plantilla tras esperar en cola; si ya no corresponde, cancela ese
mensaje sin consumir un intento y deja al dispatcher registrar la falta de plantilla.

Sin confirmación válida, la cita se conserva y **no se envía texto libre**. La
respuesta de creación incluye `customer_notice.status = not_sent`, motivo y
`templates_path`; la actividad de la cita y la conversación conservan la clave o
ruta de Plantillas. Cancelación conserva también la actividad de la cita cuando
falta plantilla. Los errores de creación del mensaje no revierten la cita y se
reflejan como `delivery_failed`; `queued` solo acredita creación local del mensaje,
no entrega de Meta. El payload de bandeja expone
`calendar_confirmation_template: { name, language, available }` para que el
frontend use la selección vigente; el nombre fijo queda como compatibilidad para
payloads anteriores.

## Preparación automática de Citas

Después de una conexión Google válida, el callback prepara los tres borradores
`cita_confirmacion`, `cita_cancelacion` y `cita_recordatorio` si la cuenta todavía
no tiene `settings.calendar_template_preparation`. Usa el modelo del CRUD y el
contenido de `Calendar::TemplateDefinitions`: UTILITY, NAMED, un idioma es/en
elegido por cuenta. No contacta a Meta ni activa recordatorios. No añade textos
de producto: los motivos de conflicto son códigos para la futura UI traducida.

Los borradores nuevos y sus recursos pendientes quedan siempre con WABA nula y
sin canal preferido, incluso con una sola WABA. Así no se elige un destino por
el administrador y no se generan copias por número. El bloqueo de cuenta cubre
la identidad sin WABA que el índice parcial de borradores no protege. Una WABA
compartida o varias WABAs no cambian la cantidad inicial: tres borradores locales.

Un único borrador homónimo exacto (nombre e idioma, dentro de la cuenta) se
reutiliza sin editarlo si su contenido satisface el contrato de Citas. La
proyección usada para validar contenido local no constituye aprobación remota.
Un borrador archivado, incompatible, ambiguo o sin su destino válido queda en
conflicto. Un homónimo remoto en la caché Cloud queda `remote_template_exists`:
se conserva y requiere selección explícita; no se adopta ni se crea otro borrador.
Un recurso previo queda `existing_resource` con su ID, conservando su selección.
Los nombres parecidos y los idiomas distintos no son la misma identidad.

La preparación guarda idioma y resultados por función bajo `account.with_lock`.
`created` y `reused` son marcas duraderas de «ya preparado»: aunque se archive o
elimine el borrador o recurso después, ni OAuth ni el reintento lo restauran.
La primera preparación es transaccional; un error revierte sus escrituras y no
impide el redirect OAuth. Las reconexiones con resultado previo, incluso con
conflictos, no vuelven a invocar el servicio. No hay backfill para cuentas conectadas.

Rutas admin bajo
`/api/v1/accounts/:account_id/integrations/calendar_connections/template_drafts`:

| Método | Resultado |
| --- | --- |
| GET | Estado local; `language` y `results` por confirmation/cancellation/reminder; sin preparación devuelve `pending` |
| POST | Preparación explícita o reintento de funciones pendientes/en conflicto; conserva las ya creadas/reutilizadas por idioma; `language` opcional es/en (efectivo por defecto) |

Cada resultado expone `status` (`pending/created/reused/conflict`), `reason` si
corresponde, `draft_id`, `draft_exists`, `archived`, `resource_id`, `resources`
(id/WABA/estado local) y `linked`. Incluye los recursos asociados al borrador
después de elegir destino, además del recurso original sin WABA. `linked` señala
un vínculo local registrado; es un agregado obsoleto. El desglose por destino revalida con el resolver local, sin contactar a Meta.
`submission_status`, `remote_status`, `submitted` y `approved` describen el último
intento por revisión del borrador, según la caché de submissions; no son prueba
de entrega ni activan consumidores. La selección y la revisión/envío siguen
siendo acciones explícitas de Plantillas. Todas las lecturas se acotan a la cuenta.
## Estado por destino y vínculo

El estado admin GET conserva `language`, `results` y todas las claves anteriores.
`linked` y `approved` globales quedan **obsoletos para decidir disponibilidad**:
representan respectivamente algún vínculo del borrador preparado y la última
revisión remota conocida de ese borrador. No acreditan disponibilidad en todas
las WABAs ni son requisitos para el camino legado.

Cada función añade `destinations`, `ready_destinations` y `total_destinations`.
Una entrada agrupa los números Cloud de la cuenta con la misma WABA e incluye
`waba_id`, `channels: [{id, name}]` (ID de Channel::Whatsapp y nombre de bandeja),
`state`, `reason`, `resource_id`, `draft_id` y `via`. Canales sin WABA configurada
no son destinos; sin destinos configurados la lista es vacía y los totales son 0.

| Estado | Significado |
| --- | --- |
| `usable` | El resolver real de envío encuentra una plantilla en el idioma efectivo para todos los números del destino. `via` distingue `linked` y `legacy_by_name`. |
| `incompatible` | Selección incompatible o versión cambiada; legado rechazado/recategorizado; o borrador aprobado que aún necesita vínculo explícito (`explicit_link_required`). |
| `pending_approval` | Envío local en proceso/revisión o espejo legado PENDING. |
| `not_submitted` | Existe borrador, pero no un envío activo para esa WABA/idioma; incluye envíos fallidos. |
| `missing` | No hay selección, borrador ni plantilla legada del idioma efectivo. |

`via: none` indica que no se resolvió una plantilla enviable. La disponibilidad
usa `Calendar::TemplateResources#resolve`: en vínculos valida ID/nombre, idioma,
APPROVED, UTILITY, NAMED, las cuatro variables de cita, botones según función y
versión congelada. El legado admite nombre fijo `cita_*`, idioma efectivo,
APPROVED y UTILITY sin exigir borrador ni recurso ni imponer retroactivamente el
contrato estructural nuevo. Un recurso pending conserva ese legado; uno
incompatible lo bloquea. Cada número se resuelve con su propio espejo; si uno no
resuelve, la WABA no se anuncia lista. El primer número que falla aporta el
motivo. La lectura puede marcar incompatible una selección cuya versión haya
cambiado, igual que el envío; no crea borradores ni consulta a Meta.

«Enviable» aquí acredita disponibilidad local de plantilla, no entrega: siguen
aplicándose destinatario, elegibilidad de la cita, política de recordatorios,
horarios y validación al entregar. No enciende recordatorios ni cambia Captain.

### Selección explícita

`POST /api/v1/accounts/:account_id/integrations/calendar_connections/template_drafts/link`
requiere administrador y JSON con `function` (confirmation/cancellation/reminder),
`channel_id` entero (ID del canal WhatsApp Cloud de esa cuenta) y exactamente una
selección:

- `draft_id` entero: toma nombre/ID remoto de la última submission de su WABA e
  idioma; no infiere identidad por un nombre parecido ni sigue ediciones locales.
- `template_name` + `remote_template_id`: strings no vacíos de la versión remota
  elegida en el espejo de ese canal.

Resuelve la WABA desde el canal y usa el idioma efectivo actual de la cuenta.
El borrador debe pertenecer a esa cuenta, WABA e idioma. Reutiliza `link!` con su
bloqueo de cuenta e índices; repetir la misma selección conserva fila, versión y
fecha de vínculo. Devuelve el estado actualizado. No requiere preparación previa.

Entrada inválida, canal ajeno/no Cloud, borrador ajeno/destino incorrecto o contrato
incompatible devuelven 422 con `error` como código (`invalid_input`,
`invalid_channel`, `cloud_channel_required`, `missing_waba`, `invalid_draft`,
`destination_mismatch`, `language`, `missing_submission`, `missing_template`,
`category`, `status`, `parameter_format`, `components`, `variables`, `buttons`).
Un intento de selección incompatible conserva ese diagnóstico en el recurso y
bloquea el fallback legado, conforme a `link!`. Un usuario ajeno a la cuenta o
un agente recibe 401 por el controlador base, sin acceso al catálogo.

Aprobar en Plantillas actualiza la submission/espejo; **nunca vincula por sí solo**.
El administrador elige POST link; el recurso queda linked; GET lo resuelve por
WABA/idioma; CustomerNotice y recordatorio humano consumen ese mismo resolver.
Captain conserva su resolver y tiempos actuales. Nada de este recorrido envía a
Meta; el envío a revisión sigue siendo otra acción explícita de Plantillas.

### Idioma preparado y efectivo

La raíz y cada función exponen `prepared_language`, `effective_language` y
`language_changed`. Antes de preparar, `prepared_language` es null y
`language_changed` es false. `language` conserva el último idioma preparado
(o el efectivo si nunca se preparó); los destinos siempre describen el idioma
efectivo, calculado por `TemplateDefinitions.language(account)` como los envíos.

POST de preparación acepta `language: "es"|"en"`; por defecto usa el efectivo
actual. Guarda resultados duraderos por idioma en
`calendar_template_preparation.languages`, y mantiene `language`/`results` para
los consumidores anteriores. Cada resultado nuevo guarda `prepared_language`.
Las marcas previas a este formato se conservan en su idioma original al preparar
otro idioma. Reintentar un idioma recupera sus resultados sin restaurar borradores
archivados/eliminados ni sustituir selecciones o versiones. Preparar en inglés no
modifica locale ni recursos/borradores en español. OAuth sigue preparando solo en
la primera conexión: un cambio de locale se diagnostica, no prepara ni aprueba
recursos automáticamente. No requiere migración ni backfill.

## Continuidad y privacidad de Citas

Contrato del brief de continuidad (2026-11-23): cerrar un calendario bloquea reservas nuevas, pero conserva mantenimiento y avisos de citas existentes mientras la conexión siga activa. Desconectar Google conserva identidad, referencias e historial; pausa avisos automáticos y la reconstrucción de recordatorios dependientes de esa conexión. La lectura debe indicar `verified: false`, sin convertir una cita en cancelada. Reconectar permite reanudar pendientes elegibles y conserva los marcadores de avisos ya enviados.

Cambiar el calendario de Captain solo afecta reservas nuevas. Listar, cancelar y mover citas anteriores debe resolver el contacto y el recurso autorizado original. Las citas nuevas deben conservar la procedencia de su creador; para citas antiguas sin procedencia, el reconciliador mantiene la selección actual por bandeja sin presentar esa selección como autoría histórica ni hacer backfill.

La lectura de agenda y del panel de contacto debe aplicar la política de conversación, incluida su extensión Enterprise. Un agente sin acceso recibe ocupación y horario, sin título privado, descripción, enlaces, contacto, conversación, autores ni actividades. Administradores y agentes autorizados conservan los detalles.

**Implementación posterior a la reproducción:** el PM ejecutó 423 ejemplos y reportó 18 fallos A1–A6 antes de los cambios (`.codex/RESULTADO-RSPEC-PM.md`). EventService separa habilitación para crear/listar disponibilidad de acceso para mantener citas. Dispatcher y Delivery humanos, Sender y reconciliador Captain pausan la conexión inactiva con log estructurado `calendar_notice_paused`, razón `connection_disconnected` e IDs de cita/conexión, sin datos del cliente. Delivery libera el claim de una cola pendiente sin consumir intento; el cron vuelve a encolarla al reconectar. Una aceptación del proveedor ya registrada se contabiliza sin reenviar. Se mantienen los filtros de fecha, horario y elegibilidad existentes: la reconexión no recupera citas vencidas ni reenvía recordatorios marcados enviados.

`Captain::AppointmentAccess` conserva acceso al recurso actualmente configurado y a citas del contacto asociadas a conversaciones de las bandejas del asistente en la misma cuenta. Cancelar, mover y confirmar resuelven la identidad original de conexión/calendario; no trasladan eventos ni hacen exclusivo al creador. El mantenimiento no depende de que la nueva conexión configurada esté activa, pero sí exige acceso a la conexión original para modificar Google. La consulta de disponibilidad para proponer un movimiento conserva por ahora el calendario configurado; EventService valida el recurso original al ejecutar el movimiento. No se promete una propuesta histórica por calendario en ese flujo.

**Migración necesaria:** aplicar `20261123120000_add_booking_actor_to_calendar_events.rb` antes de servir el código. Añade `booking_actor` jsonb con snapshot de tipo/ID/nombre/miniatura para nuevas reservas humanas o Captain. Se guarda al crear, no al importar o editar, y no se transfiere al cambiar la bandeja. La extensión Enterprise captura Captain sin acoplar OSS a su modelo. El reconciliador usa el ID histórico dentro de la cuenta; si ese asistente ya no existe, no transfiere el seguimiento. Las citas antiguas conservan `{}` sin backfill y mantienen el comportamiento anterior de selección del asistente actual de bandeja. Su avatar legado sigue siendo dinámico y no acredita autoría histórica. Los recordatorios con procedencia mantienen su emisor original mientras sus interruptores y el del canal sigan activos.

`Calendar::EventVisibility` aplica la política de conversación a agenda general, filas descartadas, listado filtrado por contacto y panel del contacto. Para eventos sin conversación vinculada se conserva la lectura anterior; esta regla no inventa un propietario privado para eventos exclusivamente Google o CRM. `verified` expresa que la conexión está activa, no una comprobación remota instantánea. El panel de conversación/contacto conserva citas desconectadas con `verified: false`; la agenda remota general sigue requiriendo conexión activa y calendario habilitado. Refrescar invitaciones omite conexiones inactivas.

**Validación pendiente:** los cambios de producción y los controles adicionales no se ejecutaron en esta sesión. El PM debe aplicar la migración en una base aislada, repetir los 423 ejemplos y todos los consumidores A7 y correr RuboCop del CI. El schema se ajustó a mano con autorización expresa del PM (solo versión y columna); falta comprobar equivalencia con el volcado real. Sin UI, cambios de plantillas, configuración productiva, backfill, Docker, navegador ni proveedores reales.

**Límite de la cola Captain:** su Sender marca el recordatorio enviado al crear el mensaje; la cola posterior usa `SendReplyJob` genérico y no el contrato de Delivery humano. Se pausa antes de crear ese mensaje, pero desconectar después de crearlo no añade revalidación en la entrega al proveedor. Ese intervalo no está cubierto por los 18 fallos reportados: requiere reproducción específica y contrato de entrega/claim Captain antes de certificar pausa de punta a punta. No se agregó un guard que descartara mensajes sin conservar su pendiente.
