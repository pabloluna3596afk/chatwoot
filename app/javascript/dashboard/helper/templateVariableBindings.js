// The link between the variables of a WhatsApp template and the CRM.
//
// A Meta variable ({{nombre}}) is only a name: whoever sends the template fills it with a text, and that text can be a
// Liquid expression ("{{ contact.first_name }}") that the backend renders when the message is sent (Liquidable for
// messages, Whatsapp::LiquidTemplateProcessorService for campaigns). This is the one table that says which name means
// which CRM value, so the template form offers those names and the send dialogs fill them in.
import { formatLiquidVariable } from './liquidVariablesHelper';

// Names of the CRM / system values, in the order the form offers them. `key` is the Liquid path.
export const SYSTEM_BINDINGS = [
  { name: 'nombre', key: 'contact.name' },
  { name: 'primer_nombre', key: 'contact.first_name' },
  { name: 'apellido', key: 'contact.last_name' },
  { name: 'correo', key: 'contact.email' },
  { name: 'telefono', key: 'contact.phone' },
  { name: 'empresa', key: 'contact.company_name' },
  { name: 'ciudad', key: 'contact.city' },
  { name: 'pais', key: 'contact.country_code' },
  { name: 'documento', key: 'contact.document_number' },
  { name: 'agente', key: 'agent.name' },
  { name: 'numero_conversacion', key: 'conversation.id' },
];

const FLOW_WRITABLE_KEYS = new Set([
  'contact.name',
  'contact.email',
  'contact.phone',
  'contact.company_name',
  'contact.city',
  'contact.document_number',
]);

// Metadata describes capabilities; server Drops remain the authority for values.
const metadata = (binding, attribute) => ({
  ...binding,
  scope: binding.group,
  canonicalPath: binding.key,
  type: attribute?.attribute_display_type || 'text',
  options: attribute?.attribute_values || [],
  readable: true,
  writable: attribute
    ? ['contact_attribute', 'conversation_attribute'].includes(
        attribute.attribute_model
      ) && !Object.keys(attribute.formula || {}).length
    : FLOW_WRITABLE_KEYS.has(binding.key),
  formula: attribute?.formula || null,
  requiresContext: [binding.key.split('.')[0]],
});

// Existing Captain aliases, offered only when requested; never added to message defaults in P1.
export const APPOINTMENT_BINDINGS = [
  { name: 'cita', key: 'appointment.title' },
  { name: 'fecha', key: 'appointment.date' },
  { name: 'hora', key: 'appointment.time' },
  { name: 'tema', key: 'appointment.title' },
  { name: 'asistente', key: 'assistant.name' },
].map(binding => metadata({ ...binding, group: 'appointment' }));

// Flow compatibility lives in the catalog, including its input and option constraints.
export const writableFor = (binding, block) => {
  if (!binding.writable || !['system', 'contact'].includes(binding.scope))
    return false;
  const { type, options } = binding;
  switch (block.type) {
    case 'short_text':
      return type === 'text' || (block.input === 'number' && type === 'number');
    case 'long_text':
    case 'checkbox':
      return type === 'text';
    case 'date':
      return ['date', 'text'].includes(type);
    case 'optin':
      return type === 'checkbox';
    case 'dropdown':
    case 'radio':
      return (
        type === 'text' ||
        (type === 'list' &&
          (block.options || []).every(option => options.includes(option.id)))
      );
    default:
      return false;
  }
};

const VARIABLE_NAME = /^[a-z][a-z0-9_]*$/;
const CONVERSATION_PREFIX = 'conversacion_';

// Every name the CRM can fill in: the system ones plus the custom attributes of the contact (named by their key)
// and of the conversation (named conversacion_<key>). A campaign has no conversation, so it gets no conversation
// values. Each is { name, key, group: 'system' | 'contact' | 'conversation', label? }.
export const buildBindings = (attributes = [], context = 'message') => {
  const isCampaign = context === 'campaign';
  const bindings = SYSTEM_BINDINGS.filter(
    binding => !(isCampaign && binding.key.startsWith('conversation.'))
  ).map(binding => metadata({ ...binding, group: 'system' }));
  const taken = new Set(bindings.map(binding => binding.name));

  (attributes || []).forEach(attribute => {
    const isConversation =
      attribute.attribute_model === 'conversation_attribute';
    if (isConversation && isCampaign) return;

    const name = isConversation
      ? `${CONVERSATION_PREFIX}${attribute.attribute_key}`
      : attribute.attribute_key;
    if (!VARIABLE_NAME.test(name) || taken.has(name)) return;

    taken.add(name);
    bindings.push(
      metadata(
        {
          name,
          key: `${isConversation ? 'conversation' : 'contact'}.custom_attribute.${attribute.attribute_key}`,
          group: isConversation ? 'conversation' : 'contact',
          label: attribute.attribute_display_name || attribute.attribute_key,
        },
        attribute
      )
    );
  });
  return bindings;
};

// { nombre: '{{ contact.name }}' }: what a variable starts with in a send dialog, by its name.
export const defaultValuesFor = bindings =>
  Object.fromEntries(
    bindings.map(binding => [binding.name, formatLiquidVariable(binding.key)])
  );

const LIQUID_PATH = /^\{\{\s*([\w.]+)\s*\}\}$/;

const read = (record, ...keys) => {
  const key = keys.find(candidate => record?.[candidate] !== undefined);
  return key ? record[key] : undefined;
};

const words = text =>
  String(text || '')
    .split(/\s+/)
    .filter(Boolean);
const capitalize = word => word.charAt(0).toUpperCase() + word.slice(1);

const contactValue = (contact, field) => {
  const extra =
    read(contact, 'additional_attributes', 'additionalAttributes') || {};
  const parts = words(contact?.name);
  const values = {
    name: contact?.name,
    first_name: parts.length ? capitalize(parts[0]) : '',
    last_name: parts.slice(1).map(capitalize).join(' '),
    email: contact?.email,
    phone: read(contact, 'phone_number', 'phoneNumber'),
    phone_number: read(contact, 'phone_number', 'phoneNumber'),
    identifier: contact?.identifier,
    company_name: extra.company_name ?? extra.companyName,
    city: extra.city,
    country_code: extra.country_code ?? extra.countryCode,
    document_number: extra.document_number ?? extra.documentNumber,
  };
  return values[field];
};

// The text a Liquid expression gives for these records ({ contact, conversation, agent }), the way the backend
// renders it; undefined for an expression that cannot be known here (appointments, the assistant...).
export const resolveLiquid = (liquid, records = {}) => {
  const path = String(liquid || '').match(LIQUID_PATH)?.[1];
  if (!path) return undefined;
  const [scope, field, ...rest] = path.split('.');
  const { contact, conversation, agent } = records;

  let value;
  if (scope === 'contact' && field === 'custom_attribute') {
    value = read(contact, 'custom_attributes', 'customAttributes')?.[rest[0]];
  } else if (scope === 'contact') {
    value = contactValue(contact, field);
  } else if (scope === 'conversation' && field === 'custom_attribute') {
    value = read(conversation, 'custom_attributes', 'customAttributes')?.[
      rest[0]
    ];
  } else if (scope === 'conversation' && field === 'id') {
    value = conversation?.id;
  } else if (scope === 'agent' && field === 'name') {
    value = agent?.available_name || agent?.availableName || agent?.name;
  } else {
    return undefined;
  }
  return value === undefined || value === null ? '' : String(value);
};
