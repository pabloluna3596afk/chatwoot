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
migración de consumidores, webhook nuevo ni cambio de presets/blueprints/Citas.
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
