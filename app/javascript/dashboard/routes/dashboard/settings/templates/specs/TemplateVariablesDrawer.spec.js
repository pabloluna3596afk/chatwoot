import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import TemplateVariablesDrawer from '../TemplateVariablesDrawer.vue';
import TemplateDataPill from '../TemplateDataPill.vue';
import { hasPendingVariables } from '../templateData';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
vi.mock('dashboard/api/whatsappTemplates', () => ({
  default: { updateTemplate: vi.fn() },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      key.endsWith('SAVE_ERROR') ? `${key}: ${values.inbox}` : key,
    te: () => false,
  }),
}));

const { dispatch, close, admin } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  close: vi.fn(),
  admin: { value: true },
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(admin.value) }),
}));
vi.mock('dashboard/api/inboxes', () => ({
  default: { updateWhatsappTemplateVariableBindings: vi.fn() },
}));
vi.mock('dashboard/composables/useTemplateBindings', () => ({
  useTemplateBindings: () => ({
    bindings: ref(
      ['name', 'email', 'phone'].map(name => ({
        id: name,
        key: `contact.${name}`,
        name,
        legacyPaths: [],
      }))
    ),
  }),
}));
vi.mock(
  'dashboard/components-next/captain/pageComponents/assistant/settings/useTemplateVariables',
  () => ({
    useTemplateVariables: () => ({
      previewValues: ref({
        'contact.name': 'Ana',
        'contact.email': 'ana@example.com',
      }),
    }),
  })
);

const template = {
  name: 'pedido',
  status: 'APPROVED',
  category: 'UTILITY',
  components: [
    {
      type: 'BODY',
      text: 'Hola {{nombre}}, pedido {{1}}, correo {{2}}',
      example: { body_text: [['ABC', 'ana@example.com']] },
    },
  ],
  variable_sources: {
    body: {
      nombre: { source: 'alias', path: 'contact.name' },
      1: { source: 'missing' },
      2: { source: 'missing' },
    },
  },
  missing_variables: ['1', '2'],
  inboxes: [
    { id: 1, name: 'Ventas', provider: '360dialog' },
    { id: 2, name: 'Soporte' },
  ],
};
const render = async (value = template) => {
  const wrapper = mount(TemplateVariablesDrawer, {
    props: { template: value },
    global: {
      stubs: {
        SidePanel: {
          methods: { open() {}, close },
          template: '<aside><slot/><slot name="footer"/></aside>',
        },
        Button: {
          props: ['label', 'disabled'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
        VariablePicker: {
          props: ['modelValue', 'disabled'],
          template:
            '<select :value="modelValue" :disabled="disabled" @change="$emit(\'update:modelValue\', $event.target.value)"><option value=""/><option value="name">Name</option><option value="email">Email</option><option value="phone">Phone</option></select>',
        },
      },
    },
  });
  wrapper.vm.open(value);
  await flushPromises();
  return wrapper;
};

describe('template variable assignment', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    admin.value = true;
  });

  it('shows automatic values and pending tokens with the amber preview', async () => {
    const wrapper = await render();
    expect(wrapper.text()).toContain('VARIABLES_DRAWER.AUTO');
    expect(wrapper.text()).toContain('VARIABLES_DRAWER.MISSING_HINT');
    expect(wrapper.findAll('select')).toHaveLength(2);
    expect(
      wrapper.get('[data-testid="send-center-preview-body"]').text()
    ).toContain('{{1}}');
    expect(
      wrapper
        .get('[data-testid="send-center-preview-body"] .text-n-amber-11')
        .text()
    ).toBe('{{1}}');
    const change = wrapper
      .findAll('button')
      .find(button => button.text().endsWith('.CHANGE'));
    await change.trigger('click');
    expect(wrapper.findAll('select')).toHaveLength(3);
  });

  it('preselects email and phone examples without writing before Save', async () => {
    const wrapper = await render();
    expect(wrapper.findAll('select')[1].element.value).toBe('email');
    expect(wrapper.findAll('select')[0].element.value).toBe('');
    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).not.toHaveBeenCalled();
    const phone = structuredClone(template);
    phone.components[0].example.body_text[0][1] = '+593 99 123 4567';
    const phoneWrapper = await render(phone);
    expect(phoneWrapper.findAll('select')[1].element.value).toBe('phone');
    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).not.toHaveBeenCalled();
  });

  it('patches each inbox sequentially and saves only picker values', async () => {
    const wrapper = await render();
    await wrapper.findAll('select')[0].setValue('name');
    await wrapper.vm.save();
    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings.mock.calls
    ).toEqual([
      [
        1,
        {
          name: 'pedido',
          variable_bindings: { 1: 'contact.name', 2: 'contact.email' },
        },
      ],
      [
        2,
        {
          name: 'pedido',
          variable_bindings: { 1: 'contact.name', 2: 'contact.email' },
        },
      ],
    ]);
    expect(dispatch).toHaveBeenCalledWith('inboxes/get', { force: true });
    expect(wrapper.emitted('saved')).toHaveLength(1);
    expect(close).toHaveBeenCalledOnce();
    expect(WhatsappTemplatesAPI.updateTemplate).not.toHaveBeenCalled();
  });

  it('keeps the panel open and identifies the failing inbox', async () => {
    InboxesAPI.updateWhatsappTemplateVariableBindings
      .mockResolvedValueOnce({})
      .mockRejectedValueOnce(new Error());
    const wrapper = await render();
    await wrapper.vm.save();
    expect(wrapper.get('[role="alert"]').text()).toContain('SAVE_ERROR');
    expect(wrapper.get('[role="alert"]').text()).toContain('Soporte');
    expect(wrapper.vm.saveError).toBeTruthy();
    expect(close).not.toHaveBeenCalled();
    expect(wrapper.emitted('saved')).toBeUndefined();
  });

  it('waits for the first inbox before starting the next PATCH', async () => {
    let finishFirst;
    InboxesAPI.updateWhatsappTemplateVariableBindings.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finishFirst = resolve;
        })
    );
    const wrapper = await render();
    const saving = wrapper.vm.save();
    await flushPromises();
    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).toHaveBeenCalledTimes(1);
    expect(close).not.toHaveBeenCalled();
    finishFirst({});
    await saving;
    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).toHaveBeenCalledTimes(2);
    expect(close).toHaveBeenCalledOnce();
  });

  it('prevents saves after approval is lost and for agents', async () => {
    const wrapper = await render();
    await wrapper.setProps({ template: { ...template, status: 'PENDING' } });
    await wrapper.vm.save();
    expect(wrapper.text()).toContain('NOT_APPROVED');
    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).not.toHaveBeenCalled();
    admin.value = false;
    const agent = await render();
    await agent.vm.save();
    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).not.toHaveBeenCalled();
  });

  it.each([
    [{ ...template, variable_sources: {}, missing_variables: [] }, 'NONE'],
    [{ ...template, missing_variables: [] }, 'AUTO'],
    [template, 'MISSING'],
    [{ ...template, category: 'AUTHENTICATION' }, null],
    [{ ...template, status: 'PENDING' }, null],
    [{ ...template, status: 'REJECTED' }, null],
  ])('renders data state for %j', (value, state) => {
    const wrapper = mount(TemplateDataPill, { props: { template: value } });
    expect(wrapper.text()).toBe(
      state ? `WHATSAPP_TEMPLATE_MGMT.DATA_STATE.${state}` : '—'
    );
    expect(hasPendingVariables(value)).toBe(Boolean(state === 'MISSING'));
  });
});
