// Alias compatibility between the variables of a WhatsApp template and the CRM.
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

// Flow compatibility lives in the catalog, including its input and option constraints.
export const writableFor = (binding, block) => {
  if (
    !binding.writable ||
    binding.managedBy ||
    !binding.writeContexts.includes('whatsapp_flow') ||
    !['system', 'contact'].includes(binding.scope)
  )
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

// { nombre: '{{ contact.name }}' }: what a variable starts with in a send dialog, by its name.
export const defaultValuesFor = bindings =>
  Object.fromEntries(
    bindings.map(binding => [
      binding.name,
      binding.expression || formatLiquidVariable(binding.key),
    ])
  );

// Do not infer paths from attribute keys. Rails supplies the literal expression.
export const catalogBindings = variables => {
  const taken = new Set(variables.flatMap(variable => variable.aliases));
  return variables
    .filter(variable => variable.available && variable.readable)
    .flatMap(variable => {
      let names = variable.aliases;
      if (!names.length) {
        let name = variable.reference.definitionId
          ? `atributo_${variable.reference.definitionId}`
          : variable.id.replace(/[^a-z0-9_]/g, '_');
        while (taken.has(name)) name += '_';
        taken.add(name);
        names = [name];
      }
      const path = variable.expression.slice(3, -3);
      return names.map(name => ({
        ...variable,
        name,
        key: path,
        canonicalPath: variable.legacyPaths[0],
        scope:
          variable.reference.kind === 'system' &&
          !['company', 'flow', 'appointment', 'assistant'].includes(
            variable.group
          )
            ? 'system'
            : variable.group,
      }));
    });
};
