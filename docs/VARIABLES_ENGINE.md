# Motor de variables — contrato de la PR A

El catálogo y la vista previa pertenecen a Rails. Las referencias de atributos
usan el ID de la definición: una clave eliminada y recreada tiene otra identidad.
Las expresiones Liquid existentes siguen siendo compatibles.

## Metadata

`GET /api/v1/accounts/:account_id/variables?surface=message`

Requiere autenticación y pertenencia a la cuenta según el controlador base.
Devuelve `schemaVersion: 1`, `definitionsVersion`, `surface`, `contexts` y
`variables`, sin valores de registros. `definitionsVersion` cambia al editar o
eliminar definiciones y al modificar la configuración de atributos de Citas.
No representa la versión de los valores de un contacto.

Cada descriptor declara `id`, `reference`, `key`, `label`, `group`, `type`,
`options`, `readable`, `writable`, `writeContexts`, `requiresContext`, `managedBy`,
`aliases`, `legacyPaths`, `expression` y `available`.

- `available` significa que la superficie admite ese contexto; no garantiza que
  una ejecución tenga registro o valor.
- Claves Unicode, puntos y guiones se conservan con acceso literal, por ejemplo
  `{{ contact.custom_attribute['nivel.vip'] }}`. No se renombran datos.
- Los alias reservados permanecen en sistema. Entre atributos se asignan por
  orden de ID; los descriptores en colisión permanecen en el catálogo.
- Las fórmulas tienen `managedBy: formula`. Los derivados habilitados de Citas
  cuyo tipo coincide con el propietario tienen `managedBy: calendar`.
  `writable: false` describe capacidad; no modifica todavía los writers.
- Empresa y Flow tienen grupos propios. No se convierten en contacto.
- Catálogo y fábrica tienen extensión Enterprise mediante `prepend_mod_with`.
  No se enumeran columnas del modelo ni se exponen credenciales.

## Preview por lote

`POST /api/v1/accounts/:account_id/variables/preview`

```json
{
  "surface": "message",
  "mode": "value",
  "texts": ["{{ contact.document_number }}", "Hola {{ contact.name }}"],
  "contexts": [{"contact_id": 12}, {"conversation_id": 34}]
}
```

`conversation_id` es el `display_id` público. `contact_id`, `inbox_id` y
`campaign_id` son IDs internos positivos de la cuenta. Solo se aceptan enteros
JSON. Una conversación impone su contacto y Bandeja; se rechazan combinaciones
incoherentes. Se consultan políticas Pundit y sus extensiones Enterprise.
El contexto de campaña requiere administrador. No se aceptan datos completos
de contacto ni un remitente arbitrario del cliente.

`surface` admite `message` (predeterminado), `campaign`, `automation`, `flow`,
`captain` y `email`. La PR A resuelve contextos base y campañas. Los contextos
locales de cita/asistente/empresa/run/mail se declaran, pero sin proveedor del
registro entregan `unavailable`; no se busca otra cita o run como respaldo.

`mode: value` coincide con los valores de parámetros de plantillas.
`mode: content` protege backticks como los mensajes. Se conservan filtros y
sintaxis Liquid. Un valor insertado con Liquid no se interpreta recursivamente.

Máximos: 100 textos, 50 contextos, 500 combinaciones y 150 000 bytes de textos.
Parámetros mal formados: `422`; registros ajenos: `404`; sin sesión, pertenencia
o permiso: `401`, siguiendo los controladores existentes.

Respuesta: `schemaVersion`, `timezone` y `results[contextIndex][textIndex]`.
Cada resultado contiene `status`, `value` y `errors` (clases, sin mensajes de
excepción):

| Estado | Significado |
|---|---|
| `value` | Se resolvió sin diagnóstico de dato faltante. `0` y `false` son valores. |
| `missing` | Dato no definido o resultado vacío; un filtro puede dar texto de respaldo. |
| `unavailable` | Una expresión referencia un contexto conocido ausente en esta ejecución. |
| `invalid` | Sintaxis, filtro o ejecución Liquid inválidos; valor `null`. |

El valor usa el render permisivo histórico. Un segundo recorrido estricto
obtiene diagnósticos, sin reinterpretar el resultado del primero.
Ambos endpoints llevan `Cache-Control: no-store, private` y no persisten mensajes.

## Paridad y fechas

`Liquidable` y preview comparten fábrica y resolver. Se conservan los Drops y la
precedencia remitente/asignado. El parser de plantillas consume el endpoint con
contexto CRM, mantiene Liquid sin editar y fija texto solo al editarlo. Cancela
peticiones antiguas con `useAbortableRequest`. Ante error muestra un aviso y
bloquea el envío hasta resolver o corregir manualmente los valores.

La decisión del dueño sobre fechas se aplica en la fábrica común: `DateDrop`
recibe `account.reporting_timezone`, con la zona Rails anterior cuando la cuenta
no configura ninguna. Preview y mensajes usan esa zona, sin cambiar `Time.zone`
global. La zona se devuelve y se muestra. Es la única corrección de política de
valores del envío además de extraer el resolver; no se modifica transporte,
conversores ni mapeo Meta. Otros consumidores de `DateDrop.new` conservan su
zona anterior hasta adoptar la fábrica.

Campañas WA/SMS usan ahora `date` en la zona de la cuenta, sin `conversation`.
`Variables::DeliveryRenderer` aplica la política de envío a los árboles de
parámetros: rechaza `missing`, `unavailable` e `invalid` con ruta y estado,
incluido un dato vacío dentro de texto no vacío. Los destinatarios omitidos
quedan en `campaign_recipients.error_message`, exportable desde la campaña.
SMS conserva su seguimiento previo de entregas; solo registra las omisiones
de variables, sin convertir ese registro parcial en totales de audiencia.
El adaptador Enterprise de texto histórico WA conserva su render permisivo
para los alias Meta existentes; los parámetros enviados sí se validan.

Flows Meta resuelven header/body/CTA antes de validar límites y guardan el
snapshot junto con el mensaje, antes de encolar el envío. Las acciones de
plantilla omiten con nota privada y razón. Esos mensajes ya resueltos se
persisten una vez: los datos insertados no vuelven a interpretarse como Liquid.
Los envíos manuales mantienen el contrato de preview de PR A y el adaptador
Liquidable previo; la migración de su selector/diagnóstico pertenece a PR C.

El endpoint público de campañas web solo usa cuenta, Bandeja, fecha y remitente
de la campaña, nunca datos del visitante. Si necesita contacto u otro contexto
ausente, omite el aviso completo de la respuesta pública. La ruta de creación
de conversación sí resuelve el contacto; ante datos faltantes revierte esa
creación. Los backticks conservan la protección histórica de campañas.

Citas concretas y su zona efectiva del calendario permanecen en el proveedor
Captain para PR E. No se inventa una cita desde los derivados del contacto.
Los locales de correo mantienen su contrato independiente hasta su migración.

## Verificación

Specs de contrato y permisos:
`spec/controllers/api/v1/accounts/variables_controller_spec.rb`.
Catálogo y paridad: `spec/services/variables/`. RSpec se ejecuta solo en CI.
Los specs frontend del parser cubren MV-01/02/03, valores de servidor frente a
registros locales diferentes, datos faltantes y fallo de red.
