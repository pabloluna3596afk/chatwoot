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
    expect(
      state.options.value.map(option => [option.value, option.disabled])
    ).toEqual([
      ['Alex', false],
      ['', true],
    ]);
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
    expect(state.options.value[0].disabled).toBe(true);
    wrapper.unmount();
  });
});
