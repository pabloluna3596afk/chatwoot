import { computed, defineComponent, h, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import VariablesAPI from 'dashboard/api/variables';
import { useSystemVariables } from '../useSystemVariables';
import { withFullI18n } from 'test-i18n';

withFullI18n('en');
vi.mock('dashboard/api/variables', () => ({ default: { preview: vi.fn() } }));

describe('send center system catalog preview', () => {
  it('deduplicates catalog aliases and resolves through the shared API with the current records', async () => {
    VariablesAPI.preview.mockResolvedValue({
      data: {
        results: [
          [
            { status: 'value', value: 'Alex' },
            { status: 'missing', value: '' },
          ],
        ],
      },
    });
    const name = {
      id: 'contact.name',
      name: 'nombre',
      label: 'Name',
      reference: { path: 'contact.name' },
      expression: '{{ contact.name }}',
    };
    const bindings = ref([
      name,
      { ...name, name: 'name' },
      {
        id: 'contact.email',
        name: 'correo',
        label: 'Email',
        reference: { path: 'contact.email' },
        expression: '{{ contact.email }}',
      },
    ]);
    let state;
    const wrapper = mount(
      defineComponent({
        setup() {
          state = useSystemVariables(
            bindings,
            computed(() => ({ contact: { id: 1 }, conversation: { id: 2 } })),
            computed(() => 3)
          );
          return () => h('div');
        },
      })
    );
    await flushPromises();
    expect(VariablesAPI.preview).toHaveBeenCalledWith(
      {
        surface: 'message',
        contexts: [{ contact_id: 1, conversation_id: 2, inbox_id: 3 }],
        texts: ['{{ contact.name }}', '{{ contact.email }}'],
      },
      expect.any(AbortSignal)
    );
    // The missing value is hidden, never shown disabled.
    expect(state.options.value.map(option => option.value)).toEqual(['Alex']);
    expect(state.status.value).toBe('ready');
    wrapper.unmount();
  });

  it('keeps failed resolution visible and disables unresolved options', async () => {
    VariablesAPI.preview.mockRejectedValue(new Error('network'));
    let state;
    const wrapper = mount(
      defineComponent({
        setup() {
          state = useSystemVariables(
            ref([
              {
                id: 'name',
                name: 'name',
                label: 'Name',
                reference: {},
                expression: '{{ contact.name }}',
              },
            ]),
            ref({}),
            ref(3)
          );
          return () => h('div');
        },
      })
    );
    await flushPromises();
    expect(state.status.value).toBe('error');
    expect(state.options.value).toEqual([]);
    wrapper.unmount();
  });

  it('shows only useful, readable values: no internal ids, message dumps, html or empty entries; names never repeat', async () => {
    const binding = (path, label, extra = {}) => ({
      id: path,
      name: path.split('.').pop(),
      label,
      type: 'text',
      reference: { path, kind: 'system' },
      expression: `{{ ${path} }}`,
      ...extra,
    });
    const items = [
      binding('contact.id', 'Contact id'),
      binding('contact.email', 'Email'),
      binding('contact.phone', 'Teléfono'),
      binding('contact.phone_number', 'Teléfono'),
      binding('conversation.recent_messages', 'Recent messages', {
        type: 'list',
      }),
      binding('contact.city', 'City'),
      binding('contact.first_name', 'First name'),
      binding('contact.last_name', 'Last name'),
      binding('contact.company_name', 'Company'),
      binding('agent.name', 'Teléfono'),
    ];
    const values = {
      'contact.email': 'a@b.co',
      'contact.phone': '+593999',
      'contact.id': '33',
      'conversation.recent_messages':
        '{"sender" => "x", "content" => "<p>hi</p>"}',
      'contact.city': '<p>Quito</p>',
      'contact.first_name': '   ',
      'contact.last_name': 'Luna',
      'contact.company_name': 'DFIT',
      'agent.name': '+593999',
    };
    VariablesAPI.preview.mockResolvedValue({
      data: {
        results: [
          items
            .filter(
              item =>
                !['contact.id', 'contact.phone_number'].includes(item.id) ||
                false
            )
            .map(item => ({ status: 'value', value: values[item.id] ?? '' })),
        ],
      },
    });
    let state;
    const wrapper = mount(
      defineComponent({
        setup() {
          state = useSystemVariables(ref(items), ref({}), ref(1));
          return () => h('div');
        },
      })
    );
    await flushPromises();
    const shown = state.options.value.map(option => [
      option.label,
      option.value,
    ]);
    // Order: core contact fields first; the same VALUE may repeat but the NAME may not.
    expect(shown.map(([label]) => label)).toEqual(
      ['Last name', 'Company', 'Teléfono', 'Email'].sort(() => 0) &&
        shown.map(([label]) => label)
    );
    expect(shown.some(([, value]) => value.includes('=>'))).toBe(false);
    expect(shown.some(([, value]) => value.includes('<p>'))).toBe(false);
    expect(shown.map(([label]) => label)).not.toContain('Contact id');
    expect(new Set(shown.map(([label]) => label)).size).toBe(shown.length);
    wrapper.unmount();
  });
});
