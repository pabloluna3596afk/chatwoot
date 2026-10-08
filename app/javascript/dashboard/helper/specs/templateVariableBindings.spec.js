import {
  SYSTEM_BINDINGS,
  APPOINTMENT_BINDINGS,
  writableFor,
  buildBindings,
  defaultValuesFor,
  resolveLiquid,
} from '../templateVariableBindings';

const attributes = [
  {
    attribute_key: 'plan',
    attribute_model: 'contact_attribute',
    attribute_display_name: 'Plan',
  },
  {
    attribute_key: 'estado',
    attribute_model: 'conversation_attribute',
    attribute_display_name: 'Estado',
  },
  { attribute_key: 'Bad Key', attribute_model: 'contact_attribute' },
  { attribute_key: 'nombre', attribute_model: 'contact_attribute' },
];

describe('buildBindings', () => {
  it('offers the CRM names even when the account has no custom attributes', () => {
    const bindings = buildBindings([], 'message');

    expect(bindings.map(binding => binding.name)).toEqual(
      SYSTEM_BINDINGS.map(binding => binding.name)
    );
    expect(bindings.every(binding => binding.group === 'system')).toBe(true);
  });

  it('adds the contact and the conversation custom attributes with valid, unique names', () => {
    const bindings = buildBindings(attributes, 'message');

    expect(bindings.find(binding => binding.name === 'plan')).toMatchObject({
      key: 'contact.custom_attribute.plan',
      group: 'contact',
      label: 'Plan',
    });
    expect(
      bindings.find(binding => binding.name === 'conversacion_estado')
    ).toMatchObject({
      key: 'conversation.custom_attribute.estado',
      group: 'conversation',
    });
    expect(bindings.filter(binding => binding.name === 'nombre')).toHaveLength(
      1
    );
    expect(bindings.some(binding => binding.name.includes(' '))).toBe(false);
  });

  it('leaves the conversation out of a campaign, which has none', () => {
    const names = buildBindings(attributes, 'campaign').map(
      binding => binding.name
    );

    expect(names).toContain('plan');
    expect(names).not.toContain('conversacion_estado');
    expect(names).not.toContain('numero_conversacion');
  });

  it('turns them into the Liquid a send dialog starts with', () => {
    const values = defaultValuesFor(buildBindings(attributes, 'message'));

    expect(values.nombre).toBe('{{ contact.name }}');
    expect(values.plan).toBe('{{ contact.custom_attribute.plan }}');
    expect(values.agente).toBe('{{ agent.name }}');
  });
});

describe('resolveLiquid', () => {
  const records = {
    contact: {
      name: 'ana pérez gómez',
      email: 'ana@example.com',
      phone_number: '+593999999999',
      custom_attributes: { plan: 'Pro' },
      additional_attributes: { company_name: 'Acme', city: 'Quito' },
    },
    conversation: { id: 42, custom_attributes: { estado: 'VIP' } },
    agent: { name: 'Pablo' },
  };

  it('gives the value the backend would render', () => {
    expect(resolveLiquid('{{ contact.name }}', records)).toBe(
      'ana pérez gómez'
    );
    expect(resolveLiquid('{{ contact.first_name }}', records)).toBe('Ana');
    expect(resolveLiquid('{{contact.last_name}}', records)).toBe('Pérez Gómez');
    expect(resolveLiquid('{{ contact.phone }}', records)).toBe('+593999999999');
    expect(resolveLiquid('{{ contact.company_name }}', records)).toBe('Acme');
    expect(resolveLiquid('{{ contact.custom_attribute.plan }}', records)).toBe(
      'Pro'
    );
    expect(
      resolveLiquid('{{ conversation.custom_attribute.estado }}', records)
    ).toBe('VIP');
    expect(resolveLiquid('{{ conversation.id }}', records)).toBe('42');
    expect(resolveLiquid('{{ agent.name }}', records)).toBe('Pablo');
  });

  it('reads camelCased records too (the compose dialog)', () => {
    const camel = {
      contact: {
        name: 'Luis',
        phoneNumber: '+593988888888',
        customAttributes: { plan: 'Basic' },
      },
    };

    expect(resolveLiquid('{{ contact.phone }}', camel)).toBe('+593988888888');
    expect(resolveLiquid('{{ contact.custom_attribute.plan }}', camel)).toBe(
      'Basic'
    );
  });

  it('is empty for a missing value and undefined for what only the backend knows', () => {
    expect(resolveLiquid('{{ contact.email }}', { contact: {} })).toBe('');
    expect(resolveLiquid('{{ appointment.date }}', records)).toBeUndefined();
    expect(resolveLiquid('Hola {{ contact.name }}', records)).toBeUndefined();
  });
});

describe('catalog metadata', () => {
  it('preserves paths and aliases, with explicit capabilities and required context', () => {
    const bindings = buildBindings(attributes);
    expect(bindings.find(item => item.name === 'nombre')).toMatchObject({
      scope: 'system',
      canonicalPath: 'contact.name',
      type: 'text',
      options: [],
      readable: true,
      writable: true,
      formula: null,
      requiresContext: ['contact'],
    });
    expect(
      bindings.find(item => item.name === 'conversacion_estado')
    ).toMatchObject({
      scope: 'conversation',
      writable: true,
      requiresContext: ['conversation'],
    });
    expect(bindings.find(item => item.name === 'agente').writable).toBe(false);
    expect(
      APPOINTMENT_BINDINGS.every(
        item => item.scope === 'appointment' && item.readable && !item.writable
      )
    ).toBe(true);
    expect(defaultValuesFor(bindings)).not.toHaveProperty('cita');
  });

  it('exposes list options and keeps formulas readable but never writable', () => {
    const bindings = buildBindings([
      {
        attribute_key: 'tier',
        attribute_model: 'contact_attribute',
        attribute_display_type: 'list',
        attribute_values: ['pro'],
      },
      {
        attribute_key: 'total',
        attribute_model: 'contact_attribute',
        attribute_display_type: 'number',
        formula: { op: 'sum' },
      },
    ]);
    const tier = bindings.find(item => item.name === 'tier');
    const total = bindings.find(item => item.name === 'total');
    expect(tier.options).toEqual(['pro']);
    expect(writableFor(tier, { type: 'radio', options: [{ id: 'pro' }] })).toBe(
      true
    );
    expect(
      writableFor(tier, { type: 'radio', options: [{ id: 'free' }] })
    ).toBe(false);
    expect(total).toMatchObject({
      readable: true,
      writable: false,
      formula: { op: 'sum' },
    });
    expect(writableFor(total, { type: 'short_text', input: 'number' })).toBe(
      false
    );
  });
});
