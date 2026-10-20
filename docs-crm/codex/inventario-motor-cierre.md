# Cierre PR0 del motor — PR A

Fecha: 2026-10-20. Worktree `wt-motor`, rama `feat/variables-engine`.
Complementa la auditoría; las rutas de código son relativas al worktree.
Inventario estático de contratos y entradas. No certifica configuraciones de
correo persistidas, integraciones externas ni datos de producción.

## Dependencia fijada

`pnpm-lock.yaml:476`: `@chatwoot/utils@0.0.57`. Se descargó el tarball exacto de
registry.npmjs.org y se verificó su SHA-512 contra la integridad del lockfile.
El paquete incluye fuentes, sin depender de sourcemaps minificados:

| Fuente del paquete | Contrato y consecuencia |
|---|---|
| `src/canned.ts:13` | `capitalizeName` conserva el resto de cada palabra; difiere de Ruby `capitalize`. |
| `src/canned.ts:28` y `:33` | Primer y último término; el resto no se convierte a minúsculas. |
| `src/canned.ts:42` | `getMessageVariables`: contact usa `conversation.meta.sender`, agent usa assignee; contacto explícito aporta custom_attributes; Bandeja llega por parámetro. No documento/país/date. |
| `src/canned.ts:96` | Sustitución por diccionario y truthiness; no ejecuta Liquid ni filtros. No preserva `false`/`0` como el resolver nuevo. |
| `src/canned.ts:111` | Detección de indefinidos omite bloques de triple backtick. |
| `src/template.ts:211` | `isWhatsAppComplete` valida medios, header, body y botones por truthiness; no conoce registros ni evalúa Liquid. |

Consumidores: `ReplyBox.vue:26` y `:487` siguen usando las utilidades de editor;
su migración corresponde a PR C. `WhatsAppTemplateParser.vue` conserva la
completitud compartida y delega exclusivamente la resolución CRM a Rails.
No se modifica ni actualiza el paquete. Tarball y extracción permanecen en `tmp/`.

## Widget y SDK: rutas completas

| Entrada | Recorrido y persistencia | Adopción posterior |
|---|---|---|
| SDK contacto | `app/javascript/entrypoints/sdk.js:139,147` → eventos iframe; `widget/App.vue:306,316` → `widget/store/modules/contacts.js:90` → `widget/api/contacts.js:18` → `Api::V1::Widget::ContactsController#update/#destroy_custom_attributes`. SetUser usa `:13`, HMAC y `identify_contact`. | PR E: adaptar writer internamente; conservar HMAC, merge/borrado y contrato público. |
| SDK conversación | `entrypoints/sdk.js:157` → `widget/App.vue:320` → `widget/store/modules/conversation/actions.js:215` (pendingCustomAttributes sin conversación) → `widget/api/conversation.js:65` → `Widget::ConversationsController#set_custom_attributes:67`/destroy. | PR E: conservar cola pendiente y semántica actual del endpoint. |
| Prechat | `widget` captura campos definidos; `Widget::ConversationsController#conversation_params` y builders reciben custom_attributes y contacto. | PR E: permisos/tipos por destino al adoptar writer. |
| API pública | `app/controllers/public/api/v1/inboxes/contacts_controller.rb:50` permite `custom_attributes`; conversación `conversations_controller.rb:64`. | Mantener source_id, HMAC y forma del payload. |
| API de cuenta | `app/controllers/api/v1/accounts/contacts_controller.rb` create/update/destroy_custom_attributes; conversación usa su endpoint existente. | No endurecer APIs en PR A. |
| Campaña web sin conversación | `Widget::CampaignsController:2` omite contacto → `app/views/api/v1/widget/campaigns/index.json.jbuilder:5` entrega texto → `widget/views/Campaigns.vue:15` → `UnreadMessageList.vue:44` → `UnreadMessage.vue:109` → Markdown. | PR B: no resolver PII en respuesta común por Bandeja. |
| Campaña web con conversación | `app/builders/campaigns/campaign_conversation_builder.rb:14,25` crea Conversation/Message y entra a Liquidable. | Es otro camino; conservar diferencia al migrar campaña. |
| Saludos y fuera de horario | `message_templates/hook_execution_service.rb:22,39` → greeting/out_of_office → Message tipo template → Liquidable. Bienvenida visual del widget sigue siendo configuración, no Message. | PR E: contextos anónimos y doble render por separado. |

El endpoint de metadata nuevo pertenece a la cuenta autenticada. No se añade al
widget público ni se entregan valores personales en respuestas de campañas.

## Importadores, exportación y empresa

| Escritor/lector | Contrato observado |
|---|---|
| CSV `app/services/data_import/contact_manager.rb:61,78,85` | Documento a columna con normalización; empresa/ciudad a adicionales; columnas restantes se mezclan en JSON custom_attributes. No requiere una definición por clave importada. |
| `app/services/data_imports/importer.rb:302,311,366,388` | Contactos existentes actualizados con merge y `update_columns`; contactos/conversaciones nuevos reciben valores y metadata de la fuente. |
| `data_imports/intercom/source.rb:123,138` | Proyecta custom_attributes y metadata de Intercom a contacto/conversación. |
| `data_imports/freshdesk/source.rb:144,152` y `metadata.rb:2` | Proyección propia de campos; metadata técnica no se convierte automáticamente en definición CRM. |
| `account/contacts_export_job.rb:46,114` | Lee columnas y valores JSON según definiciones. No es interpolación de envío. |
| `account/conversations_export_job.rb:39,46,95` | Lee JSON directamente; tampoco debe evaluar Liquid de un dato exportado. |
| EE `companies_controller.rb:43,93,97,105` | Permisos y feature de empresa propios; merge/borrado de custom_attributes. El catálogo distingue `company_attribute`, sin promoverlo a contacto ni habilitar envío company inexistente. |
| Calendar `appointment_attributes/provisioner.rb:27`, `updater.rb:20` | Provisiona/reutiliza definiciones y escribe exclusivamente derivados habilitados cuyo tipo coincide; fuente son CalendarEvent de cuenta/contacto. `managedBy` nuevo refleja ese propietario. |

Importar una clave sin definición no la hace aparecer en el catálogo. Liquid
libre aún puede leerla. No hay autoprovisión masiva, backfill ni cambio de datos.
La migración a un writer común corresponde a PR D/E, preservando locks, snapshot,
ResponseToken y unicidad de documento del Flow de WhatsApp.

## Correo: productores y namespaces

| Productor | Drops/locales y alcance |
|---|---|
| `app/mailers/application_mailer.rb:43,54` | account, user, conversation, inbox; global_config y action_url. Los `locals.merge` sin asignación no agregan attachment_url/imported_contacts/failed_contacts; no se asume lo contrario al catalogar. |
| `agent_notifications/conversation_notifications_mailer.rb:60,64` | Añade notification_settings_url, message y los registros de notificación. |
| EE `enterprise/agent_notifications/conversation_notifications_mailer.rb:33` | Añade sla_policy con Drop propio. Se conserva fuera del selector CRM general. |
| `team_notifications/automation_notification_mailer.rb:22,29` | contact + custom_message. Insertar custom_message no vuelve a ejecutar Liquid contenido en él. |
| `administrator_notifications/base_mailer.rb:28` | meta proviene de cada invocación de send_notification. Account/channel/integrations/compliance aportan claves técnicas propias. |
| `portal_instructions_mailer.rb:17` | Local cname_record; no es atributo del contacto. |
| `conversation_reply_mailer.rb:223` | agent, contact y message para respuestas salientes. Body HTML tiene render en MessageBuilder/EmailHelper separado. |
| `lib/action_view/template/handlers/liquid.rb:16,26,34` | Combina Drops con locals; filtros y registers del controlador. Usa render! en desarrollo/test y render en otros entornos. |
| `app/models/email_template.rb:112`, `email_templates/db_resolver_service.rb:35,58` | Plantillas persistidas: validación sintáctica y precedencia Bandeja/cuenta/instalación. Se preserva contrato; no se leen datos reales. |

El apéndice enumera todos los archivos Liquid de `app/views/mailers` y el layout,
con sus expresiones/tags y líneas. Incluye variables locales de bucles. No se
convierte `meta`, `chat_message`, `attachment`, `global_config` ni `sla_policy` en
atributos de contacto. Los proveedores de locales se adoptarán por superficie.

## Matriz de fixtures y responsables

| Caso | Fuente autoritativa | Cobertura PR A / siguiente |
|---|---|---|
| Documento solo columna + alias documento | ContactDrop.document_number | RSpec resolver + requests; regresión frontend MV-01. |
| MARÍA del CARMEN / público distinto | ContactDrop y UserDrop | RSpec paridad + regresión frontend MV-02. |
| Columna EC frente a additional country_code US | ContactDrop.country_code; callback usa additional.country | Fixture conserva country EC para no falsear el caso; MV-03. |
| Unicode, punto, guion, alias reservado/duplicado | Definición por ID + acceso Liquid literal | Catalog/resolver specs; ninguna clave se renombra. |
| false / 0 / valor que contiene Liquid | Liquid/Drops | Resolver specs; sin segundo render del resultado. |
| Sin contexto / sintaxis/filtro inválido | Resolver y registro de contextos | Status unavailable/missing/invalid; API sin mensajes de excepción. |
| Campaña y remitente | Campaign.sender y mismo ContactDrop | Paridad CampaignTemplateService; date/conversation siguen ausentes hasta PR B. |
| Fecha junto a medianoche | reporting_timezone de cuenta | Fábrica común de mensajes/preview; consumidores sin migrar conservan DateDrop anterior. |
| Derivados Citas / fórmula | Propietario y enabled_keys | Metadata read-only; enforcement writer queda para PR D. |
| Empresa / Flow run / tool / mail locals | Contextos explícitos del proveedor | Grupos separados y ausencia declarada; proveedores completos en PR D/E. |

PR0 queda cerrado para las cuatro familias pendientes de la auditoría. La
verificación dinámica backend queda en CI por instrucción del brief; no se
confunde inventario de fuentes con certificación de integraciones externas.

## Apéndice: plantillas Liquid de correo

| Archivo:línea | Expresión o tag |
|---|---|
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:6 | {{ meta.instance_url }} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:7 | {{ meta.account_id }} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:8 | {{ meta.account_name }} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:9 | {{ meta.marked_for_deletion_at }} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:10 | {{ meta.deleted_at }} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:11 | {{ meta.deletion_reason }} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:14 | {% if meta.deleted_user_count > 0 %} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:16 | {{ meta.deleted_user_count }} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:17 | {% for user in meta.soft_deleted_users %} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:18 | {{ user.user_id }}; {{ user.user_email }}; {% unless forloop.last %}; {% endunless %} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:19 | {% endfor %} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:21 | {% else %} |
| app/views/mailers/administrator_notifications/account_compliance_mailer/account_deleted.liquid:25 | {% endif %} |
| app/views/mailers/administrator_notifications/account_notification_mailer/account_deletion_for_inactivity.liquid:3 | {{ meta.account_name }}; {{ meta.deletion_date }} |
| app/views/mailers/administrator_notifications/account_notification_mailer/account_deletion_for_inactivity.liquid:7 | {{ meta.deletion_date }}; {{ action_url }} |
| app/views/mailers/administrator_notifications/account_notification_mailer/account_deletion_for_inactivity.liquid:11 | {{ meta.deletion_date }} |
| app/views/mailers/administrator_notifications/account_notification_mailer/account_deletion_user_initiated.liquid:3 | {{ meta.account_name }}; {{ meta.deletion_date }} |
| app/views/mailers/administrator_notifications/account_notification_mailer/account_deletion_user_initiated.liquid:12 | {{ action_url }} |
| app/views/mailers/administrator_notifications/account_notification_mailer/automation_rule_disabled.liquid:3 | {{meta['rule_name']}} |
| app/views/mailers/administrator_notifications/account_notification_mailer/automation_rule_disabled.liquid:7 | {{action_url}} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_export_complete.liquid:7 | {{ action_url }} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_import_complete.liquid:5 | {{meta['imported_contacts']}} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_import_complete.liquid:7 | {{meta['failed_contacts']}} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_import_complete.liquid:9 | {% if meta['failed_contacts'] == 0 %} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_import_complete.liquid:11 | {{action_url}} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_import_complete.liquid:13 | {% else %} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_import_complete.liquid:15 | {{ action_url }} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_import_complete.liquid:17 | {% endif %} |
| app/views/mailers/administrator_notifications/account_notification_mailer/contact_import_failed.liquid:1 | Sin expresiones Liquid |
| app/views/mailers/administrator_notifications/account_notification_mailer/conversation_export_complete.liquid:7 | {{ action_url }} |
| app/views/mailers/administrator_notifications/account_notification_mailer/usage_limit_warning.liquid:3 | {{meta['account_name']}}; {{meta['percent']}}; {{meta['total_count']}} |
| app/views/mailers/administrator_notifications/account_notification_mailer/usage_limit_warning.liquid:6 | {{action_url}} |
| app/views/mailers/administrator_notifications/channel_notifications_mailer/email_disconnect.liquid:7 | {{action_url}} |
| app/views/mailers/administrator_notifications/channel_notifications_mailer/facebook_disconnect.liquid:7 | {{action_url}} |
| app/views/mailers/administrator_notifications/channel_notifications_mailer/instagram_disconnect.liquid:7 | {{action_url}} |
| app/views/mailers/administrator_notifications/channel_notifications_mailer/whatsapp_disconnect.liquid:7 | {{action_url}} |
| app/views/mailers/administrator_notifications/integrations_notification_mailer/dialogflow_disconnect.liquid:1 | Sin expresiones Liquid |
| app/views/mailers/administrator_notifications/integrations_notification_mailer/openai_disconnect.liquid:6 | {{action_url}} |
| app/views/mailers/administrator_notifications/integrations_notification_mailer/slack_disconnect.liquid:6 | {{action_url}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/assigned_conversation_new_message.liquid:1 | {{user.available_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/assigned_conversation_new_message.liquid:6 | {{action_url}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:1 | {{user.available_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:5 | {% for chat_message in conversation.recent_messages %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:8 | {% if chat_message.sender == user.available_name %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:10 | {% else %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:11 | {{chat_message.sender}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:12 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:17 | {% if chat_message.content %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:18 | {{chat_message.content}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:19 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:21 | {% if chat_message.attachments %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:22 | {% for attachment in chat_message.attachments %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:23 | {{ attachment }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:24 | {% endfor %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:25 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:27 | {% endfor %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_assignment.liquid:30 | {{action_url}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:1 | {{user.available_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:4 | {{ action_url }}; {{conversation.display_id}}; {{ inbox.name }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:5 | {{ conversation.contact_name }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:8 | {% for chat_message in conversation.recent_messages %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:11 | {% if chat_message.sender == user.available_name %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:13 | {% else %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:14 | {{chat_message.sender}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:15 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:20 | {% if chat_message.content %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:21 | {{chat_message.content}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:22 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:24 | {% if chat_message.attachments %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:25 | {% for attachment in chat_message.attachments %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:26 | {{ attachment }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:27 | {% endfor %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:28 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_creation.liquid:30 | {% endfor %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:1 | {{user.available_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:3 | {{message.sender_display_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:5 | {{message.text_content}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:9 | {% for chat_message in conversation.recent_messages %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:12 | {% if chat_message.sender == user.available_name %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:14 | {% else %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:15 | {{chat_message.sender}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:16 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:21 | {% if chat_message.content %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:22 | {{chat_message.content}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:23 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:25 | {% if chat_message.attachments %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:26 | {% for attachment in chat_message.attachments %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:27 | {{ attachment }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:28 | {% endfor %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:29 | {% endif %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:31 | {% endfor %} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_mention.liquid:33 | {{ action_url }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/participating_conversation_new_message.liquid:1 | {{user.available_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/participating_conversation_new_message.liquid:5 | {{action_url}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_first_response.liquid:1 | {{user.available_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_first_response.liquid:4 | {{conversation.display_id}}; {{ inbox.name }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_first_response.liquid:5 | {{ sla_policy.name }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_first_response.liquid:9 | {{action_url}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_next_response.liquid:1 | {{user.available_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_next_response.liquid:4 | {{conversation.display_id}}; {{ inbox.name }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_next_response.liquid:5 | {{ sla_policy.name }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_next_response.liquid:9 | {{action_url}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_resolution.liquid:1 | {{user.available_name}} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_resolution.liquid:4 | {{conversation.display_id}}; {{ inbox.name }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_resolution.liquid:5 | {{ sla_policy.name }} |
| app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_resolution.liquid:9 | {{action_url}} |
| app/views/mailers/portal_instructions_mailer/send_cname_instructions.liquid:4 | {{ cname_record &#124; split: ' ' &#124; first }} |
| app/views/mailers/portal_instructions_mailer/send_cname_instructions.liquid:11 | {{ cname_record }} |
| app/views/mailers/team_notifications/automation_notification_mailer/conversation_creation.liquid:3 | {{ custom_message }} |
| app/views/mailers/team_notifications/automation_notification_mailer/conversation_creation.liquid:6 | {{ action_url }} |
| app/views/mailers/team_notifications/automation_notification_mailer/conversation_updated.liquid:1 | {{user.available_name}} |
| app/views/mailers/team_notifications/automation_notification_mailer/conversation_updated.liquid:4 | {{ custom_message }} |
| app/views/mailers/team_notifications/automation_notification_mailer/conversation_updated.liquid:7 | {{ action_url }} |
| app/views/mailers/team_notifications/automation_notification_mailer/message_created.liquid:1 | {{user.available_name}} |
| app/views/mailers/team_notifications/automation_notification_mailer/message_created.liquid:4 | {{ custom_message }} |
| app/views/mailers/team_notifications/automation_notification_mailer/message_created.liquid:7 | {{ action_url }} |
| app/views/layouts/mailer/base.liquid:93 | {% assign brand_name = global_config['BRAND_NAME'] %} |
| app/views/layouts/mailer/base.liquid:94 | {% if brand_name == nil %} |
| app/views/layouts/mailer/base.liquid:95 | {% assign brand_name = 'ChatHub' %} |
| app/views/layouts/mailer/base.liquid:96 | {% endif %} |
| app/views/layouts/mailer/base.liquid:97 | {% assign brand_url = global_config['BRAND_URL'] %} |
| app/views/layouts/mailer/base.liquid:113 | {{ content_for_layout }} |
| app/views/layouts/mailer/base.liquid:120 | {% if brand_name != '' %} |
| app/views/layouts/mailer/base.liquid:124 | {% if brand_url != nil and brand_url != '' %} |
| app/views/layouts/mailer/base.liquid:125 | {{ brand_url }}; {{ brand_name }} |
| app/views/layouts/mailer/base.liquid:126 | {% else %} |
| app/views/layouts/mailer/base.liquid:127 | {{ brand_name }} |
| app/views/layouts/mailer/base.liquid:128 | {% endif %} |
| app/views/layouts/mailer/base.liquid:131 | {% endif %} |
| app/views/layouts/mailer/base.liquid:132 | {% if notification_settings_url != nil and notification_settings_url != '' %} |
| app/views/layouts/mailer/base.liquid:136 | {{ notification_settings_url }} |
| app/views/layouts/mailer/base.liquid:139 | {% endif %} |
