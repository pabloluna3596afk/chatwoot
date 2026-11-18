import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import AssistantMessagingForm from './AssistantMessagingForm.vue';
import AssistantAPI from 'dashboard/api/captain/assistant';
import CaptainInboxesAPI from 'dashboard/api/captain/inboxes';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import { useAlert } from 'dashboard/composables';

const {
  linkedInboxes,
  inboxRecords,
  dispatch,
  drawerOpen,
  templatePreviewOpen,
} = vi.hoisted(() => ({
  linkedInboxes: { value: [] },
  inboxRecords: { value: [] },
  dispatch: vi.fn(async () => ({})),
  drawerOpen: vi.fn(),
  templatePreviewOpen: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: name =>
    ref(
      name === 'captainInboxes/getRecords'
        ? linkedInboxes.value
        : inboxRecords.value
    ),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, assistantId: 3 } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/captain/assistant', () => ({
  default: { allowResource: vi.fn() },
}));
vi.mock('dashboard/api/captain/inboxes', () => ({
  default: {
    get: vi.fn(async () => ({ data: { payload: [] } })),
    updateAppointments: vi.fn(async () => ({})),
  },
}));
vi.mock('dashboard/api/inboxes', () => ({
  default: {
    updateWhatsappTemplateVariableBindings: vi.fn(async () => ({})),
  },
}));
vi.mock('dashboard/api/whatsappFlows', () => ({
  default: { list: vi.fn(async () => ({ data: { payload: [] } })) },
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getConnections: vi.fn(async () => ({ data: { payload: [] } })) },
}));
vi.mock('./useTemplateVariables', () => ({
  useTemplateVariables: () => ({
    variableOptions: ref([
      { key: 'contact.name', label: 'Nombre del contacto', description: 'Ana' },
    ]),
    previewValues: ref({}),
  }),
}));

const approvedTemplate = {
  name: 'pedido_listo',
  language: 'es',
  category: 'UTILITY',
  status: 'APPROVED',
  components: [{ type: 'BODY', text: 'Hola {{nombre}}' }],
};
const whatsappInbox = (id, extra = {}) => ({
  id,
  name: `Ventas ${id}`,
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
  phone_number: '+593 99 111 2233',
  provider_config: { business_account_id: `waba-${id}` },
  appointments_enabled: true,
  message_templates: [approvedTemplate],
  ...extra,
});
const mountForm = async ({
  inboxes = [whatsappInbox(10)],
  assistant = {},
} = {}) => {
  linkedInboxes.value = inboxes.map(inbox => ({ ...inbox }));
  inboxRecords.value = inboxes.map(inbox => ({ ...inbox }));
  const wrapper = mount(AssistantMessagingForm, {
    props: {
      assistant: {
        id: 3,
        config: {
          messaging: {
            version: 2,
            revision: 4,
            inboxes: inboxes
              .filter(item => item.channel_type === 'Channel::Whatsapp')
              .map(item => ({
                inbox_id: item.id,
                enabled: true,
                mode: 'auto',
                excluded: { templates: [], flows: [] },
                included_marketing: [],
                reviewed: { templates: {}, flows: {} },
                notes: {},
              })),
          },
        },
        envios: {
          template_cap: { cap: 50, used: 12 },
          inboxes: inboxes
            .filter(item => item.channel_type === 'Channel::Whatsapp')
            .map(item => ({
              inbox_id: item.id,
              waba_id: `waba-${item.id}`,
              counts: { available: 1 },
              resources: [
                {
                  resource: {
                    name: 'pedido_listo',
                    language: 'es',
                    category: 'UTILITY',
                  },
                  state: 'available',
                  can_send: true,
                  note: 'Confirmar el pedido',
                  processed_params: { body: { nombre: '{{ contact.name }}' } },
                },
              ],
            })),
        },
        ...assistant,
      },
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsToggleSection: {
          name: 'SettingsToggleSection',
          props: ['modelValue', 'header', 'description', 'hideToggle'],
          emits: ['update:modelValue'],
          template:
            '<div><span>{{ header }}</span><button v-if="!hideToggle" role="switch" :aria-checked="modelValue" @click="$emit(\'update:modelValue\', !modelValue)"></button><slot /><slot name="hiddenToggle" /></div>',
        },
        Button: {
          props: ['label', 'disabled', 'ariaLabel', 'to'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
        Banner: { template: '<div><slot /></div>' },
        TabBar: {
          props: ['tabs', 'initialActiveTab'],
          emits: ['tabChanged'],
          template:
            '<div data-testid="inbox-tabs"><button v-for="tab in tabs" :key="tab.inboxId" @click="$emit(\'tabChanged\', tab)">{{ tab.label }} {{ tab.count }}</button></div>',
        },
        ComboBox: {
          props: ['options', 'modelValue', 'label'],
          emits: ['update:modelValue'],
          template:
            '<label>{{ label }}<select data-testid="inbox-combo" :value="modelValue" @change="$emit(\'update:modelValue\', label === \'CAPTAIN.ASSISTANTS.ENVIOS.INBOX_LABEL\' ? Number($event.target.value) : $event.target.value)"><option v-for="option in options" :key="option.value" :value="option.value">{{ option.label }}</option></select></label>',
        },
        Dialog: {
          props: ['title'],
          emits: ['confirm'],
          template:
            '<div><span>{{ title }}</span><slot /><button data-testid="dialog-confirm" @click="$emit(\'confirm\')">confirm</button></div>',
          methods: { open: vi.fn(), close: vi.fn() },
        },
        Input: {
          props: ['modelValue', 'label'],
          emits: ['update:modelValue'],
          template:
            '<label>{{ label }}<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
        },
        TextArea: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template: '<textarea :value="modelValue" />',
        },
        FlowPreviewDrawer: {
          name: 'FlowPreviewDrawer',
          template: '<div />',
          methods: { open: drawerOpen },
        },
        CaptainTemplatePreview: {
          name: 'CaptainTemplatePreview',
          props: ['template', 'params', 'complete', 'available', 'inboxName'],
          template: '<div />',
          methods: { open: templatePreviewOpen },
        },
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('AssistantMessagingForm · Envíos por bandeja', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    linkedInboxes.value = [];
    inboxRecords.value = [];
  });

  it('does not render a selector for one WhatsApp inbox and shows the daily cap', async () => {
    const wrapper = await mountForm();

    expect(wrapper.find('[data-testid="inbox-tabs"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="inbox-combo"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Ventas 10');
    expect(wrapper.vm.capUsed).toBe(12);
    expect(wrapper.vm.capValue).toBe(50);
    wrapper.vm.expanded[10] = true;
    await wrapper.vm.$nextTick();
    expect(
      wrapper.findAll('[data-testid="messaging-template-row"]')
    ).toHaveLength(1);
  });

  it('uses tabs with pending counts for mixed inboxes and selects the requested inbox', async () => {
    const inboxes = [
      whatsappInbox(10),
      { id: 11, name: 'Chat web', channel_type: 'Channel::WebWidget' },
      { id: 12, name: 'Correo', channel_type: 'Channel::Email' },
    ];
    const wrapper = await mountForm({
      inboxes,
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 12 },
          inboxes: [
            {
              inbox_id: 10,
              resources: [
                {
                  resource: { name: 'pedido_listo', language: 'es' },
                  state: 'needs_data',
                },
              ],
            },
          ],
        },
      },
    });

    expect(wrapper.find('[data-testid="inbox-tabs"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inbox-tabs"]').text()).toContain(
      'Ventas 10 1'
    );
    await wrapper
      .find('[data-testid="inbox-tabs"] button:nth-child(2)')
      .trigger('click');
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.ONLY_WHATSAPP');
    expect(wrapper.text()).toContain('Chat web');
    expect(
      wrapper.findAll('[data-testid="messaging-template-row"]')
    ).toHaveLength(0);
    await wrapper
      .find('[data-testid="inbox-tabs"] button:nth-child(3)')
      .trigger('click');
    expect(wrapper.text()).toContain('Correo');
    expect(
      wrapper.findAll('[data-testid="messaging-template-row"]')
    ).toHaveLength(0);
  });

  it('shows a WhatsApp inbox with no templates without rendering resource rows', async () => {
    const wrapper = await mountForm({
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 12 },
          inboxes: [{ inbox_id: 10, resources: [] }],
        },
      },
    });

    wrapper.vm.expanded[10] = true;
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('Ventas');
    expect(
      wrapper.findAll('[data-testid="messaging-template-row"]')
    ).toHaveLength(0);
  });

  it('uses a searchable inbox selector for ten inboxes', async () => {
    const inboxes = Array.from({ length: 10 }, (_, index) =>
      whatsappInbox(index + 1)
    );
    const wrapper = await mountForm({
      inboxes,
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 12 },
          inboxes: [
            {
              inbox_id: 1,
              resources: [
                {
                  resource: { name: 'pedido_listo', language: 'es' },
                  state: 'needs_data',
                },
              ],
            },
          ],
        },
      },
    });

    expect(wrapper.find('[data-testid="inbox-combo"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inbox-tabs"]').exists()).toBe(false);
    expect(
      wrapper.find('[data-testid="inbox-combo"] option').attributes('value')
    ).toBe('1');
    expect(wrapper.find('[data-testid="inbox-combo"] option').text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PENDING_COUNT'
    );
    await wrapper.get('[data-testid="inbox-combo"]').setValue('2');
    expect(wrapper.vm.selectedInboxId).toBe(2);
  });

  it('shows the translated empty re-engagement state without an empty template interpolation', async () => {
    const wrapper = await mountForm();
    const followup = wrapper
      .text()
      .slice(
        wrapper.text().indexOf('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.TITLE')
      );

    expect(followup).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.NO_TEMPLATE'
    );
    expect(followup).not.toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.MISSING_HERE'
    );
    expect(followup).not.toContain('«»');
  });

  it('disables the inbox appointments switch while assistant appointments are off', async () => {
    const wrapper = await mountForm({
      assistant: { config: { appointments: { enabled: false } } },
    });
    const disabledSwitch = wrapper.find('[aria-disabled="true"]');

    expect(disabledSwitch.attributes('role')).toBe('switch');
    expect(disabledSwitch.attributes('aria-checked')).toBe('false');
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.ASSISTANT_OFF'
    );
    expect(wrapper.text()).not.toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.INSIDE'
    );
  });

  it('saves the versioned messaging payload through the existing save action', async () => {
    const wrapper = await mountForm();
    await wrapper.find('input').setValue('73');
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');

    const [payload] = wrapper.emitted('submit')[0];
    expect(payload.assistantPayload.config.messaging).toMatchObject({
      version: 2,
      revision: 4,
      inboxes: [expect.objectContaining({ inbox_id: 10, mode: 'auto' })],
    });
    expect(payload.dailyCap).toBe(73);
  });

  it('shows the daily cap exhausted notice when usage reaches the configured limit', async () => {
    const wrapper = await mountForm({
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 50 },
          inboxes: [{ inbox_id: 10, resources: [] }],
        },
      },
    });

    expect(wrapper.vm.capUsed).toBe(50);
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.CAP.REACHED');
  });

  it.each(['new', 'changed', 'needs_review'])(
    'calls the server allow action for a %s resource',
    async state => {
      AssistantAPI.allowResource.mockResolvedValue({ data: {} });
      const wrapper = await mountForm({
        assistant: {
          envios: {
            template_cap: { cap: 50, used: 12 },
            inboxes: [
              {
                inbox_id: 10,
                waba_id: 'waba-10',
                resources: [
                  {
                    resource: { name: 'pedido_listo', language: 'es' },
                    state,
                  },
                ],
              },
            ],
          },
        },
      });
      wrapper.vm.expanded[10] = true;
      await wrapper.vm.$nextTick();
      const allow = wrapper
        .findAll('button')
        .find(
          button => button.text() === 'CAPTAIN.ASSISTANTS.ENVIOS.ROW_ALLOW'
        );
      await allow.trigger('click');

      expect(AssistantAPI.allowResource).toHaveBeenCalledWith({
        assistantId: 3,
        inboxId: 10,
        kind: 'template',
        key: 'waba-10:pedido_listo|es',
      });
    }
  );

  it('renders all server review states when Ver y excluir is expanded', async () => {
    const states = [
      'available',
      'excluded',
      'needs_data',
      'pending',
      'rejected',
      'unsupported',
      'authentication',
      'marketing_off',
      'new',
      'changed',
      'needs_review',
      'not_published_here',
    ];
    const wrapper = await mountForm({
      assistant: {
        config: {
          messaging: {
            version: 2,
            revision: 4,
            inboxes: [
              {
                inbox_id: 10,
                enabled: true,
                mode: 'auto',
                excluded: {
                  templates: ['waba-10:template_1|es'],
                  flows: [],
                },
              },
            ],
          },
        },
        envios: {
          template_cap: { cap: 50, used: 12 },
          inboxes: [
            {
              inbox_id: 10,
              waba_id: 'waba-10',
              resources: [
                ...states.map((state, index) => ({
                  resource: {
                    name: `template_${index}`,
                    language: 'es',
                    category: 'UTILITY',
                  },
                  state,
                  missing: state === 'needs_data' ? ['nombre'] : [],
                })),
                {
                  resource: { id: 77 },
                  state: 'not_published_here',
                },
              ],
            },
          ],
        },
      },
    });
    await wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.SHOW')
      )
      .trigger('click');

    expect(
      wrapper.findAll('[data-testid="messaging-template-row"]')
    ).toHaveLength(states.length);
    states.forEach(state => {
      expect(wrapper.text()).toContain(
        `CAPTAIN.ASSISTANTS.ENVIOS.STATES.${state.toUpperCase()}`
      );
    });
    expect(wrapper.findAll('[data-testid="messaging-flow-row"]')).toHaveLength(
      1
    );
    expect(wrapper.find('[data-testid="messaging-flow-row"]').text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.STATES.NOT_PUBLISHED_HERE'
    );
  });

  it('toggles a resource exclusion from its visible row switch', async () => {
    const wrapper = await mountForm();
    await wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.SHOW')
      )
      .trigger('click');
    const rowSwitch = wrapper.findAll(
      '[data-testid="messaging-template-row"] button[role="switch"]'
    )[0];

    await rowSwitch.trigger('click');
    expect(wrapper.vm.permissionEntries[10].excluded.templates).toContain(
      'waba-10:pedido_listo|es'
    );
  });

  it('opens the template preview from its row eye button', async () => {
    const wrapper = await mountForm();
    wrapper.vm.expanded[10] = true;
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="messaging-template-row"] button')
      .trigger('click');

    expect(wrapper.vm.selectedRow.resource.name).toBe('pedido_listo');
    expect(
      wrapper.findComponent({ name: 'CaptainTemplatePreview' }).props()
    ).toMatchObject({
      template: approvedTemplate,
      params: { body: { nombre: '{{ contact.name }}' } },
      complete: true,
      available: true,
      inboxName: 'Ventas 10',
    });
  });

  it('persists appointment inbox toggle through the existing inbox API', async () => {
    const wrapper = await mountForm();
    await wrapper
      .findAllComponents({ name: 'SettingsToggleSection' })[1]
      .vm.$emit('update:modelValue', false);
    await flushPromises();

    expect(CaptainInboxesAPI.updateAppointments).toHaveBeenCalledWith({
      assistantId: 3,
      inboxId: 10,
      appointmentsEnabled: false,
    });
  });

  it('writes variable bindings locally and refreshes the assistant payload', async () => {
    const wrapper = await mountForm({
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 12 },
          inboxes: [
            {
              inbox_id: 10,
              waba_id: 'waba-10',
              resources: [
                {
                  resource: { name: 'pedido_listo', language: 'es' },
                  state: 'needs_data',
                  missing: ['nombre'],
                },
              ],
            },
          ],
        },
      },
    });
    wrapper.vm.expanded[10] = true;
    await wrapper.vm.$nextTick();
    await wrapper
      .findAll('button')
      .find(
        button => button.text() === 'CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.ASSIGN'
      )
      .trigger('click');
    await wrapper.get('select').setValue('contact.name');
    await wrapper.findAll('[data-testid="dialog-confirm"]')[1].trigger('click');

    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).toHaveBeenCalledWith(10, {
      name: 'pedido_listo',
      variable_bindings: { nombre: 'contact.name' },
    });
    expect(dispatch).toHaveBeenCalledWith('captainAssistants/show', 3);
  });

  it('uses the local bindings API and includes the flow notice in its preview', async () => {
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: { payload: [{ id: 77, name: 'Solicitud', definition: {} }] },
    });
    const wrapper = await mountForm({
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 12 },
          inboxes: [
            {
              inbox_id: 10,
              resources: [
                { resource: { id: 77 }, state: 'not_published_here' },
              ],
            },
          ],
        },
      },
    });
    wrapper.vm.expanded[10] = true;
    await wrapper.vm.$nextTick();
    await wrapper
      .find('[data-testid="messaging-flow-row"] button')
      .trigger('click');

    expect(drawerOpen).toHaveBeenCalledWith(
      expect.objectContaining({
        notice: 'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_FLOW_UNPUBLISHED',
      })
    );
    expect(AssistantAPI.allowResource).not.toHaveBeenCalled();
  });

  it('reports a 409 conflict when allowing a stale resource', async () => {
    AssistantAPI.allowResource.mockRejectedValue({ response: { status: 409 } });
    const wrapper = await mountForm({
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 12 },
          inboxes: [
            {
              inbox_id: 10,
              waba_id: 'waba-10',
              resources: [
                {
                  resource: { name: 'pedido_listo', language: 'es' },
                  state: 'changed',
                },
              ],
            },
          ],
        },
      },
    });
    wrapper.vm.expanded[10] = true;
    await wrapper.vm.$nextTick();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CAPTAIN.ASSISTANTS.ENVIOS.ROW_ALLOW')
      .trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('CAPTAIN.ASSISTANTS.ENVIOS.CONFLICT');
  });
});
