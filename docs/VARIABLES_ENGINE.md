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
  `writable: false` se aplica también en `Variables::Writer` para las superficies migradas.
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

`conversation_id` es el `display_id` público. `contact_id`, `inbox_id`,
`campaign_id` y `flow_run_id` son IDs internos positivos de la cuenta. Solo se aceptan enteros
JSON. Una conversación impone su contacto y Bandeja; se rechazan combinaciones
incoherentes. Se consultan políticas Pundit y sus extensiones Enterprise.
El contexto de campaña requiere administrador. No se aceptan datos completos
de contacto ni un remitente arbitrario del cliente.

`surface` admite `message` (predeterminado), `campaign`, `automation`, `flow`,
`captain` y `email`. La PR A resuelve contextos base y campañas. La PR F admite
`flow_run_id` solo en superficie `flow`, junto con `conversation_id`: el run se
busca dentro de esa conversación y se aplica su política de acceso. No se
selecciona automáticamente un run activo. Los contextos locales sin proveedor
del registro entregan `unavailable`; no se busca otra cita o run como respaldo.

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
Los locales de correo conservan su contrato; la PR F resuelve el texto configurable
`custom_message` antes de insertarlo como local, sin reinterpretar sus valores.

## Verificación

Specs de contrato y permisos:
`spec/controllers/api/v1/accounts/variables_controller_spec.rb`.
Catálogo y paridad: `spec/services/variables/`. RSpec se ejecuta solo en CI.
Los specs frontend del parser cubren MV-01/02/03, valores de servidor frente a
registros locales diferentes, datos faltantes y fallo de red.

## Captain y escritura (PR E, alcance A1/A2)

Captain usa `ContextFactory` con un proveedor Enterprise para asistente/cita
concreta y `DeliveryRenderer` para mappings guardados. Una variable faltante,
contexto ausente o expresion invalida omite el mensaje completo. Recordatorios y
reactivacion registran la omision y dejan nota privada; mensajeria devuelve
`missing_variables`. La ultima razon (plantilla, slot, estado y fecha UTC, sin
valores del cliente) queda en `assistant.config.variable_delivery_error`, visible
en todas las paginas de configuracion del asistente. Indica la ultima omision,
no un diagnostico de que todos los contactos actuales esten incompletos.

Solo las referencias legacy cuyo `processed_params` es nil conservan el fallback
y el guion anteriores. No se migran implicitamente al guardar otros ajustes.
Los snapshots ya resueltos no vuelven a interpretar Liquid insertado desde datos.
`date.*` usa la zona de cuenta. La cita concreta sigue formateandose con la zona
efectiva de EventService (actualmente cuenta o el default Google Calendar);
no existe una columna independiente de zona por calendario en este esquema.

`Variables::Ownership` es la unica regla de propiedad usada por Catalog y por
la metadata aditiva `managed_by` de las definiciones. `Variables::Writer` valida
destinos de acciones y captura de WhatsApp Flow y construye sus atributos.
Las entradas API/prechat de contacto, conversacion y empresa aplican la misma
regla a updates, creacion y borrado. Reemplazar un JSON tampoco permite borrar
implicitamente derivados. Un intento de escritura en un campo gestionado se
rechaza con el error existente `ParameterMissing` (HTTP 422); las acciones y
snapshots Flow viejos omiten destinos que ya no son escribibles. Calendar y los
recomputadores de formulas mantienen sus escrituras internas como propietarios.
Los editores de atributos de contacto, conversacion y empresa respetan metadata
de propiedad; el selector ya filtraba estos destinos desde PR D.

`ValueNormalizer` conserva los tipos de acciones y resuelve cada elemento de
`multi_list` antes de devolverlo. Los valores JSON de API y respuestas Flow
siguen siendo datos literales: no ejecutan Liquid suministrado por un visitante.
Por compatibilidad, API/prechat conservan claves JSON sin definicion.
No se impone una nueva coercion de tipos a esos contratos existentes.

## Cierre de superficies (PR F)

`ContextFactory` recibe un `flow_run` explícito y expone sus valores como
`flow.x` y `flow.variables.x`, dentro del grupo Flow. El nombre `variables` se
reserva para el objeto completo; una clave del run llamada `variables` se lee
mediante `flow.variables.variables`. No se agrega un scope oculto en `Liquidable`.
El envío diferido de Flow resuelve contenido y botones antes de persistirlos,
conserva los backticks y marca el snapshot como resuelto para evitar una segunda
interpolación. Las notas y las acciones de captura del Flow usan el mismo contexto.
Un envío incompleto se omite, deja nota privada y avanza con `skipped` en el trail.

Las notificaciones de equipo resuelven `custom_message` antes de insertarlo en
el correo, con el run explícito cuando proceden de un Flow. Los saludos de bandeja
usan el mismo resolver y la zona de cuenta. Ambos omiten textos incompletos o
inválidos con nota privada localizada; los valores insertados siguen siendo
literales. Se retira `AutomationRules::MessageRendererService`, sin consumidores.
No se cambian los demás locales o plantillas de correo del sistema.

Las herramientas HTTP de Captain (V1 a través de su wrapper y V2) cargan contacto
y conversación desde IDs de estado limitados a la cuenta del asistente. Usan la
fábrica común para URL, cuerpo y formato de respuesta. Se conservan parámetros
directos y alias `r`/`response`; los Drops disponibles tienen precedencia sobre
parámetros homónimos. Una variable faltante impide la petición y devuelve ruta y
estado localizados. Un fallo al resolver la respuesta se informa después de la
petición; no puede deshacer una operación HTTP ya realizada. Autenticación,
SafeFetch y el manejo de errores de transporte mantienen sus contratos.

API y prechat siguen usando `Writer` y guardando JSON literal. Los importadores
CSV, Intercom y Freshdesk también pasan sus atributos por el writer, respetando
Calendar y fórmulas. CSV informa intentos de escritura protegida en el archivo de
rechazados; los externos conservan su manejo de errores por registro.

MV-16 se resuelve con avisos, sin crear definiciones automáticamente: inferir
tipos de CSV o promover metadata técnica de proveedores cambiaría el catálogo
de la cuenta. `ImportDiagnostics` acumula solo claves sin definición por scope,
sin valores, en el resultado de la importación. El correo de finalización CSV
incluye el aviso. Los externos muestran los avisos en su registro descargable y
terminan `completed_with_errors`; los avisos no suman registros ficticios a
`total_records` ni alteran los importados. El formato de entrada y los valores
guardados se conservan. Crear la definición con la misma clave hace visible el
valor existente, sin duplicarlo. La metadata de `additional_attributes.source`
no se transforma en atributos CRM.

No hay migraciones ni cambios de frontend, campañas, proveedores de mensajería,
Panel AI, plantillas aprobadas en Meta o cobros. Las campañas conservan la regla
de no crear conversaciones al enviarse. La compatibilidad Captain sin mappings
descrita en PR E continúa vigente. El alcance F está implementado con specs por
superficie; la confirmación integrada queda pendiente de RSpec en CI.
