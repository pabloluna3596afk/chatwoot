import catalog from 'dashboard/components-next/variable-picker/specs/catalog.json';
import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import AssistantMessagingForm from './AssistantMessagingForm.vue';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import { isSupportedForCaptain } from './captainTemplates';

const { captainInboxRecords, inboxRecords } = vi.hoisted(() => ({
  captainInboxRecords: { value: [{ id: 10 }] },
  inboxRecords: {
    value: [
      {
        id: 10,
        name: 'Soporte',
        channel_type: 'Channel::Whatsapp',
        message_templates: [],
      },
    ],
  },
}));

const approved = (name, extra = {}) => ({
  name,
  language: 'es',
  status: 'APPROVED',
  category: 'UTILITY',
  components: [{ type: 'BODY', text: 'Hola {{nombre}}' }],
  ...extra,
});
const inbox = {
  id: 10,
  name: 'Soporte',
  channel_type: 'Channel::Whatsapp',
  message_templates: [
    approved('reserva'),
    approved('con_imagen', {
      components: [
        { type: 'HEADER', format: 'IMAGE' },
        { type: 'BODY', text: 'x' },
      ],
    }),
    approved('pendiente', { status: 'PENDING' }),
  ],
};
vi.mock('dashboard/api/variables', () => ({
  default: {
    catalog: vi.fn(async () => ({
      data: {
        variables: catalog.variables
          .filter(item => item.reference.kind === 'system')
          .map(item => ({ ...item, available: item.group !== 'company' })),
      },
    })),
  },
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: name =>
    ref(
      {
        'attributes/getAttributes': [],
        'captainInboxes/getRecords': captainInboxRecords.value,
        'inboxes/getInboxes': inboxRecords.value,
      }[name]
    ),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { assistantId: 3 } }),
}));
vi.mock('dashboard/api/whatsappFlows', () => ({
  default: { list: vi.fn() },
}));

const DialogStub = {
  props: ['disableConfirmButton'],
  template:
    '<div><slot /><button data-testid="confirm" :disabled="disableConfirmButton" @click="$emit(\'confirm\')" /></div>',
  methods: { open: vi.fn(), close: vi.fn() },
};
const ComboStub = {
  props: ['modelValue', 'options'],
  emits: ['update:modelValue'],
  template: '<div class="combo" />',
};

const mountForm = (assistant = { config: {} }) =>
  mount(AssistantMessagingForm, {
    props: { assistant },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Dialog: DialogStub,
        ComboBox: ComboStub,
        SettingsToggleSection: {
          name: 'SettingsToggleSection',
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template: '<div><slot /></div>',
        },
        CapabilitySummary: {
          name: 'CapabilitySummary',
          template: '<div data-testid="capability-summary-stub" />',
        },
        WhatsAppTemplateParser: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });

describe('AssistantMessagingForm', () => {
  beforeEach(() => {
    captainInboxRecords.value = [{ id: 10 }];
    inboxRecords.value = [inbox];
    // mockReset is on for the whole project: the answer is set before every test.
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: {
        payload: [
          { id: 7, name: 'Datos de reserva' },
          { id: 8, name: 'Encuesta' },
        ],
      },
    });
  });

  it('shows the template switch even without WhatsApp inboxes', async () => {
    captainInboxRecords.value = [];
    const wrapper = mountForm();
    await flushPromises();
    expect(
      wrapper.get('[data-testid="messaging-templates-toggle"]').exists()
    ).toBe(true);
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.MESSAGING.NO_INBOXES'
    );
    expect(
      wrapper.find('[data-testid="messaging-inbox-toggle"]').exists()
    ).toBe(false);
    captainInboxRecords.value = [{ id: 10 }];
  });

  it('places the saved capabilities summary after the switch and before inbox settings', async () => {
    const wrapper = mountForm();
    await flushPromises();
    const children = wrapper.find('[data-testid="messaging-form"]').element
      .children;
    const switchIndex = [...children].findIndex(child =>
      child.matches('[data-testid="messaging-templates-toggle"]')
    );
    const summaryIndex = [...children].findIndex(child =>
      child.matches('[data-testid="capability-summary-stub"]')
    );
    const dividerIndex = [...children].findIndex(child =>
      child.textContent.includes(
        'CAPTAIN.ASSISTANTS.CAPABILITIES.SECTION_BELOW'
      )
    );
    const contentIndex = [...children].findIndex(child =>
      child.matches('[data-testid="messaging-flows"]')
    );
    expect(switchIndex).toBeLessThan(summaryIndex);
    expect(summaryIndex).toBeLessThan(dividerIndex);
    expect(dividerIndex).toBeLessThan(contentIndex);
  });

  it('starts off with nothing allowed and says Captain sends nothing', async () => {
    const wrapper = mountForm();
    await flushPromises();
    expect(
      wrapper
        .findComponent('[data-testid="messaging-inbox-toggle"]')
        .props('modelValue')
    ).toBe(false);
    expect(wrapper.find('[data-testid="messaging-flows-empty"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="messaging-templates-empty"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="messaging-limits"]').exists()).toBe(
      true
    );
  });

  it('shows what was saved and flags a resource that is no longer available', async () => {
    const wrapper = mountForm({
      config: {
        messaging: {
          inboxes: [
            {
              inbox_id: 10,
              enabled: true,
              flows: [
                { flow_id: 7, purpose: 'Pedir datos' },
                { flow_id: 99, purpose: 'Borrado' },
              ],
              templates: [
                { name: 'reserva', language: 'es', purpose: 'Confirmar' },
              ],
            },
          ],
        },
      },
    });
    await flushPromises();
    const rows = wrapper.findAll('[data-testid="messaging-flow-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Datos de reserva');
    expect(rows[1].text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.MESSAGING.UNAVAILABLE'
    );
    expect(
      wrapper.findAll('[data-testid="messaging-template-row"]')
    ).toHaveLength(1);
  });

  it('wraps long WhatsApp resource rows below md and keeps desktop rows single-line', async () => {
    const wrapper = mountForm({
      config: {
        messaging: {
          inboxes: [
            {
              inbox_id: 10,
              enabled: true,
              flows: [{ flow_id: 7, purpose: 'Reserva' }],
              templates: [
                { name: 'reserva', language: 'es', purpose: 'Confirmar' },
              ],
            },
          ],
        },
      },
    });
    await flushPromises();

    expect(
      wrapper.get('[data-testid="messaging-flow-row"]').classes()
    ).toContain('flex-wrap');
    expect(
      wrapper.get('[data-testid="messaging-flow-row"]').classes()
    ).toContain('md:flex-nowrap');
    expect(
      wrapper.get('[data-testid="messaging-template-row"]').classes()
    ).toContain('flex-wrap');
    expect(
      wrapper.get('[data-testid="messaging-template-row"]').classes()
    ).toContain('md:flex-nowrap');
    const addTemplateButton = wrapper.get(
      '[data-testid="messaging-add-template"]'
    ).element;
    expect(addTemplateButton.parentElement.classList).toContain('flex-wrap');
  });

  it('adds a Flow with its purpose and saves the whole messaging block, without empty inboxes', async () => {
    const wrapper = mountForm({ config: { allow_paid_templates: true } });
    await flushPromises();
    wrapper.vm.draft.resource = 7;
    wrapper.vm.draft.purpose = '  Pedir datos  ';
    wrapper.vm.addFlow();
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    const [payload] = wrapper.emitted('submit')[0];
    expect(payload.config.allow_paid_templates).toBe(true);
    expect(payload.config.messaging).toEqual({
      inboxes: [
        {
          inbox_id: 10,
          enabled: false,
          flows: [{ flow_id: 7, purpose: 'Pedir datos' }],
          templates: [],
        },
      ],
    });
  });

  it.each([false, true])(
    'preserves allow_paid_templates=%s when saving without touching the switch',
    async allowPaidTemplates => {
      const wrapper = mountForm({
        config: { allow_paid_templates: allowPaidTemplates },
      });
      await flushPromises();
      await wrapper.get('[data-testid="messaging-save"]').trigger('click');

      expect(wrapper.emitted('submit')[0][0].config.allow_paid_templates).toBe(
        allowPaidTemplates
      );
      expect(wrapper.find('[data-testid="messaging-paid"]').exists()).toBe(
        false
      );
    }
  );

  it.each([false, true])(
    'saves allow_paid_templates=%s only when the existing Save button is pressed',
    async initialValue => {
      const wrapper = mountForm({
        config: { allow_paid_templates: initialValue },
      });
      await flushPromises();
      wrapper
        .findComponent('[data-testid="messaging-templates-toggle"]')
        .vm.$emit('update:modelValue', !initialValue);

      expect(wrapper.emitted('submit')).toBeUndefined();
      await wrapper.get('[data-testid="messaging-save"]').trigger('click');
      expect(wrapper.emitted('submit')[0][0].config.allow_paid_templates).toBe(
        !initialValue
      );
    }
  );

  it('resynchronizes the template switch when the assistant prop changes', async () => {
    const wrapper = mountForm({ config: { allow_paid_templates: false } });
    await wrapper.setProps({
      assistant: { config: { allow_paid_templates: true } },
    });

    expect(
      wrapper
        .findComponent('[data-testid="messaging-templates-toggle"]')
        .props('modelValue')
    ).toBe(true);
  });

  it('offers only approved text templates Captain can fill', async () => {
    const wrapper = mountForm();
    await flushPromises();
    expect(wrapper.vm.templateChoices.map(option => option.value)).toEqual([
      'reserva|es',
    ]);
  });

  it('lets the owner change the purpose of what is already allowed', async () => {
    const wrapper = mountForm({
      config: {
        messaging: {
          inboxes: [
            {
              inbox_id: 10,
              enabled: true,
              flows: [{ flow_id: 7, purpose: 'Antes' }],
              templates: [],
            },
          ],
        },
      },
    });
    await flushPromises();
    wrapper
      .get('[data-testid="messaging-flow-row"]')
      .findComponent({ name: 'Input' })
      .vm.$emit('update:modelValue', 'Después');
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    expect(
      wrapper.emitted('submit')[0][0].config.messaging.inboxes[0].flows[0]
        .purpose
    ).toBe('Después');
  });

  it('keeps a separate switch for every inbox', async () => {
    const wrapper = mountForm({
      config: {
        messaging: {
          inboxes: [
            {
              inbox_id: 10,
              enabled: true,
              flows: [{ flow_id: 7, purpose: '' }],
              templates: [],
            },
          ],
        },
      },
    });
    await flushPromises();
    const toggle = () =>
      wrapper.findComponent('[data-testid="messaging-inbox-toggle"]');
    expect(toggle().props('modelValue')).toBe(true);
    toggle().vm.$emit('update:modelValue', false);
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    expect(wrapper.emitted('submit')[0][0].config.messaging).toEqual({
      inboxes: [
        {
          inbox_id: 10,
          enabled: false,
          flows: [{ flow_id: 7, purpose: '' }],
          templates: [],
        },
      ],
    });
  });

  it('does not add a template until every variable has its value', async () => {
    const wrapper = mountForm();
    await flushPromises();
    wrapper.vm.draft.resource = 'reserva|es';
    wrapper.vm.draft.purpose = 'Confirmar';
    expect(wrapper.vm.draftComplete).toBe(false);
    wrapper.vm.addTemplate();
    expect(wrapper.vm.current.templates).toHaveLength(0);

    wrapper.vm.draft.params = { body: { nombre: '{{ contact.first_name }}' } };
    expect(wrapper.vm.draftComplete).toBe(true);
    wrapper.vm.addTemplate();
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    expect(
      wrapper.emitted('submit')[0][0].config.messaging.inboxes[0].templates
    ).toEqual([
      {
        name: 'reserva',
        language: 'es',
        purpose: 'Confirmar',
        processed_params: { body: { nombre: '{{ contact.first_name }}' } },
      },
    ]);
  });

  it('flags a saved template whose variables are not filled and lets the owner fix them', async () => {
    const wrapper = mountForm({
      config: {
        messaging: {
          inboxes: [
            {
              inbox_id: 10,
              enabled: true,
              flows: [],
              templates: [{ name: 'reserva', language: 'es', purpose: '' }],
            },
          ],
        },
      },
    });
    await flushPromises();
    expect(wrapper.vm.templateRows[0].complete).toBe(false);
    wrapper.vm.openVariablesDialog(0);
    wrapper.vm.draft.params = { body: { nombre: '{{ contact.name }}' } };
    wrapper.vm.addTemplate();
    expect(wrapper.vm.templateRows[0].complete).toBe(true);
  });

  it('removes what was allowed', async () => {
    const wrapper = mountForm({
      config: {
        messaging: {
          inboxes: [
            {
              inbox_id: 10,
              enabled: true,
              flows: [{ flow_id: 7, purpose: '' }],
              templates: [],
            },
          ],
        },
      },
    });
    await flushPromises();
    wrapper.vm.removeFlow(0);
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    expect(wrapper.emitted('submit')[0][0].config.messaging.inboxes).toEqual([
      { inbox_id: 10, enabled: true, flows: [], templates: [] },
    ]);
  });
});

describe('isSupportedForCaptain', () => {
  it('rejects media headers, dynamic links, copy codes and Flow buttons', () => {
    const body = { type: 'BODY', text: 'x' };
    expect(isSupportedForCaptain({ components: [body] })).toBe(true);
    expect(
      isSupportedForCaptain({
        components: [{ type: 'HEADER', format: 'VIDEO' }, body],
      })
    ).toBe(false);
    expect(
      isSupportedForCaptain({
        components: [
          body,
          {
            type: 'BUTTONS',
            buttons: [{ type: 'URL', url: 'https://x/{{1}}' }],
          },
        ],
      })
    ).toBe(false);
    expect(
      isSupportedForCaptain({
        components: [
          body,
          { type: 'BUTTONS', buttons: [{ type: 'COPY_CODE' }] },
        ],
      })
    ).toBe(false);
    expect(
      isSupportedForCaptain({
        components: [body, { type: 'BUTTONS', buttons: [{ type: 'FLOW' }] }],
      })
    ).toBe(false);
    expect(
      isSupportedForCaptain({
        components: [
          body,
          {
            type: 'BUTTONS',
            buttons: [
              { type: 'URL', url: 'https://x.com' },
              { type: 'QUICK_REPLY' },
            ],
          },
        ],
      })
    ).toBe(true);
  });
});
