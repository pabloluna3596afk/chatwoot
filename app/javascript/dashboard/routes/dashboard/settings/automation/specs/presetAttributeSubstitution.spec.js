import { replaceAttributeKey } from '../presetAttributeSubstitution';

describe('replaceAttributeKey', () => {
  it('replaces attribute_key in a schedule object', () => {
    const schedule = {
      kind: 'days_since_attribute',
      attribute_key: 'fecha_venta',
      days: 15,
    };
    replaceAttributeKey(schedule, 'fecha_venta', 'fecha_compra_real');
    expect(schedule.attribute_key).toBe('fecha_compra_real');
  });

  it('replaces attribute_key wherever it appears across schedule AND actions — the seguimiento_30d case', () => {
    const schedule = {
      kind: 'days_since_attribute',
      attribute_key: 'fecha_seguimiento',
      days: 30,
    };
    const actions = [
      { action_name: 'send_message', action_params: ['hola'] },
      {
        action_name: 'update_conversation_custom_attribute',
        action_params: [
          { attribute_key: 'fecha_seguimiento', value: '{{ date.today }}' },
        ],
      },
      { action_name: 'notify_assignee', action_params: [] },
    ];

    replaceAttributeKey(schedule, 'fecha_seguimiento', 'fecha_ultimo_contacto');
    replaceAttributeKey(actions, 'fecha_seguimiento', 'fecha_ultimo_contacto');

    expect(schedule.attribute_key).toBe('fecha_ultimo_contacto');
    expect(actions[1].action_params[0].attribute_key).toBe(
      'fecha_ultimo_contacto'
    );
    // Untouched siblings must survive — this is a targeted replace, not a wipe.
    expect(actions[1].action_params[0].value).toBe('{{ date.today }}');
    expect(actions[0]).toEqual({
      action_name: 'send_message',
      action_params: ['hola'],
    });
  });

  it('does not touch a different attribute_key', () => {
    const conditions = [
      {
        attribute_key: 'status',
        filter_operator: 'equal_to',
        values: ['open'],
      },
    ];
    replaceAttributeKey(conditions, 'fecha_venta', 'fecha_compra_real');
    expect(conditions[0].attribute_key).toBe('status');
  });

  it('handles null/undefined/primitive nodes without throwing', () => {
    expect(() => replaceAttributeKey(null, 'a', 'b')).not.toThrow();
    expect(() => replaceAttributeKey(undefined, 'a', 'b')).not.toThrow();
    expect(() => replaceAttributeKey('a string', 'a', 'b')).not.toThrow();
    expect(() => replaceAttributeKey(42, 'a', 'b')).not.toThrow();
  });

  it('leaves an empty conditions array untouched', () => {
    const conditions = [];
    replaceAttributeKey(conditions, 'fecha_venta', 'fecha_compra_real');
    expect(conditions).toEqual([]);
  });
});
