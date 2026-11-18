import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import AssistantMessagingForm from './AssistantMessagingForm.vue';
import AssistantAPI from 'dashboard/api/captain/assistant';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import AccountAPI from 'dashboard/api/account';

const {
  linkedInboxes,
  inboxRecords,
  dispatch,
  drawerOpen,
  templatePreviewOpen,
  adminAccess,
} = vi.hoisted(() => ({
  linkedInboxes: { value: [] },
  inboxRecords: { value: [] },
  dispatch: vi.fn(async () => ({})),
  drawerOpen: vi.fn(),
  templatePreviewOpen: vi.fn(),
  adminAccess: { value: true },
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
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(adminAccess.value) }),
}));
vi.mock('dashboard/api/account', () => ({
  default: { update: vi.fn(async () => ({})) },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, assistantId: 3 } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/captain/assistant', () => ({
  default: {
    allowResource: vi.fn(),
    show: vi.fn(async () => ({ data: {} })),
    update: vi.fn(async (_id, payload) => ({ data: payload })),
  },
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
          allow_paid_templates: true,
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
            '<div><span>{{ header }}</span><span>{{ description }}</span><button v-if="!hideToggle" role="switch" :aria-checked="modelValue" @click="$emit(\'update:modelValue\', !modelValue)"></button><slot /><slot name="hiddenToggle" /></div>',
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
            '<div data-testid="inbox-tabs"><button v-for="tab in tabs" :key="tab.inboxId" @click="$emit(\'tabChanged\', tab)">{{ tab.label }} ({{ tab.count }})</button></div>',
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
  dispatch.mockImplementation(async name =>
    name === 'captainAssistants/show'
      ? {
          ...wrapper.props('assistant'),
          config:
            AssistantAPI.update.mock.lastCall?.[1]?.config ||
            wrapper.props('assistant').config,
        }
      : {}
  );
  await flushPromises();
  return wrapper;
};

describe('AssistantMessagingForm · Envíos por bandeja', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    adminAccess.value = true;
    linkedInboxes.value = [];
    inboxRecords.value = [];
  });

  it('does not render a selector for one WhatsApp inbox and shows the daily cap', async () => {
    const wrapper = await mountForm();

    expect(
      wrapper
        .find('[data-testid="inbox-tabs"]:not([data-testid="resource-tabs"])')
        .exists()
    ).toBe(false);
    expect(wrapper.find('[data-testid="inbox-combo"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Ventas 10');
    expect(wrapper.vm.capUsed).toBe(12);
    expect(wrapper.vm.capValue).toBe(50);
    wrapper.vm.activeResourceIndex = 1;
    await wrapper.vm.$nextTick();
    expect(
      wrapper.findAll('[data-testid="messaging-template-row"]')
    ).toHaveLength(1);
  });

  it('filters out non-WhatsApp inboxes from the selector', async () => {
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

    expect(
      wrapper
        .find('[data-testid="inbox-tabs"]:not([data-testid="resource-tabs"])')
        .exists()
    ).toBe(false);
    expect(wrapper.text()).not.toContain('Chat web');
    expect(wrapper.text()).not.toContain('Correo');
    expect(wrapper.vm.selectedInboxId).toBe(10);
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

    wrapper.vm.activeResourceIndex = 1;
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
    expect(
      wrapper
        .find('[data-testid="inbox-tabs"]:not([data-testid="resource-tabs"])')
        .exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="inbox-combo"] option').attributes('value')
    ).toBe('1');
    expect(wrapper.find('[data-testid="inbox-combo"] option').text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PENDING_COUNT'
    );
    await wrapper.get('[data-testid="inbox-combo"]').setValue('2');
    expect(wrapper.vm.selectedInboxId).toBe(2);
  });

  it('shows one resource tab at a time, including zero counts', async () => {
    const wrapper = await mountForm();
    expect(wrapper.get('[data-testid="resource-tabs"]').text()).toContain(
      'TABS.FLOWS (0)'
    );
    expect(wrapper.get('[data-testid="resource-tabs"]').text()).toContain(
      'TABS.TEMPLATES (1)'
    );
    expect(
      wrapper.find('[data-testid="messaging-template-row"]').exists()
    ).toBe(false);
    await wrapper
      .get('[data-testid="resource-tabs"] button:nth-child(2)')
      .trigger('click');
    expect(
      wrapper.find('[data-testid="messaging-template-row"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="messaging-flow-row"]').exists()).toBe(
      false
    );
  });

  it('disables paid template switches without losing choices or affecting Flows', async () => {
    const wrapper = await mountForm();
    const saved = JSON.stringify(wrapper.vm.permissionEntries);
    wrapper.vm.activeResourceIndex = 1;
    wrapper.vm.paidTemplates = false;
    await wrapper.vm.$nextTick();
    const row = wrapper.get('[data-testid="messaging-template-row"]');
    expect(row.classes()).toContain('opacity-50');
    expect(
      row.get('button[role="switch"]').attributes('disabled')
    ).toBeDefined();
    expect(row.get('button[role="switch"]').attributes('aria-checked')).toBe(
      'true'
    );
    expect(wrapper.find('[data-testid="templates-paid-off"]').exists()).toBe(
      true
    );
    expect(JSON.stringify(wrapper.vm.permissionEntries)).toBe(saved);
    wrapper.vm.paidTemplates = true;
    await wrapper.vm.$nextTick();
    expect(
      row.get('button[role="switch"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('keeps a toggled row in its load-time group and preserves stored notes on save', async () => {
    const wrapper = await mountForm();
    wrapper.vm.activeResourceIndex = 1;
    wrapper.vm.permissionEntries[10].notes = {
      'template:waba-10:pedido_listo|es': 'Existing owner note',
    };
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="template-READY"] button[role="switch"]')
      .trigger('click');
    expect(
      wrapper
        .get('[data-testid="template-READY"] button[role="switch"]')
        .attributes('aria-checked')
    ).toBe('false');
    expect(wrapper.text()).not.toContain('Existing owner note');
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    expect(
      AssistantAPI.update.mock.lastCall[1].config.messaging.inboxes[0].notes
    ).toEqual({
      'template:waba-10:pedido_listo|es': 'Existing owner note',
    });
  });

  it('keeps list-mode owner notes and mappings when a row is switched off and back on', async () => {
    const template = {
      name: 'pedido_listo',
      language: 'es',
      purpose: 'Existing purpose',
      processed_params: { body: { nombre: '{{ contact.name }}' } },
    };
    const wrapper = await mountForm({
      assistant: {
        config: {
          allow_paid_templates: true,
          messaging: {
            version: 2,
            revision: 4,
            inboxes: [
              {
                inbox_id: 10,
                enabled: true,
                mode: 'list',
                templates: [template],
              },
            ],
          },
        },
      },
    });
    wrapper.vm.activeResourceIndex = 1;
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="messaging-template-row"] button[role="switch"]')
      .trigger('click');
    await wrapper
      .get('[data-testid="messaging-template-row"] button[role="switch"]')
      .trigger('click');
    expect(wrapper.vm.permissionEntries[10].templates).toEqual([template]);
  });

  it('shows only WhatsApp guidance for a web-only inbox and no paid controls', async () => {
    const wrapper = await mountForm({
      inboxes: [{ id: 11, name: 'Web', channel_type: 'Channel::WebWidget' }],
    });
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.NO_WHATSAPP');
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.find('[data-testid="resource-tabs"]').exists()).toBe(false);
  });

  it('removes notes and the moved Citas and Seguimiento summaries', async () => {
    const wrapper = await mountForm();
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.find('[data-testid="messaging-followup"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-testid="messaging-appointments"]').exists()
    ).toBe(false);
  });

  it('saves the versioned messaging payload through the existing save action', async () => {
    const wrapper = await mountForm();
    await wrapper.find('input').setValue('73');
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');

    const payload = AssistantAPI.update.mock.lastCall[1];
    expect(payload.config.messaging).toMatchObject({
      version: 2,
      revision: 4,
      inboxes: [expect.objectContaining({ inbox_id: 10, mode: 'auto' })],
    });
    expect(AccountAPI.update).toHaveBeenCalledWith('', {
      captain_template_daily_cap: 73,
    });
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
    'queues a %s resource until configuration has been saved',
    async state => {
      AssistantAPI.allowResource.mockResolvedValue({
        data: {
          config: {
            messaging: {
              revision: 5,
              inboxes: [{ inbox_id: 10, reviewed: {}, included_marketing: [] }],
            },
          },
        },
      });
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
      wrapper.vm.activeResourceIndex = 1;
      await wrapper.vm.$nextTick();
      await wrapper
        .get('[data-testid="messaging-template-row"] button[role="switch"]')
        .trigger('click');

      expect(AssistantAPI.allowResource).not.toHaveBeenCalled();
      await wrapper.get('[data-testid="messaging-save"]').trigger('click');
      await flushPromises();
      expect(AssistantAPI.update.mock.invocationCallOrder.at(-1)).toBeLessThan(
        AssistantAPI.allowResource.mock.invocationCallOrder[0]
      );
      expect(AssistantAPI.allowResource).toHaveBeenCalledWith({
        assistantId: 3,
        inboxId: 10,
        kind: 'template',
        key: 'waba-10:pedido_listo|es',
        revision: 4,
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
    wrapper.vm.activeResourceIndex = 1;
    wrapper.vm.expanded['10:template:BLOCKED'] = true;
    await wrapper.vm.$nextTick();

    expect(
      wrapper.findAll('[data-testid="messaging-template-row"]')
    ).toHaveLength(states.length - 1);
    expect(wrapper.findAll('[data-testid="template-READY"] li')).toHaveLength(
      2
    );
    expect(
      wrapper.findAll('[data-testid="template-PERMISSION"] li')
    ).toHaveLength(5);
    expect(wrapper.findAll('[data-testid="template-BLOCKED"] li')).toHaveLength(
      4
    );
    wrapper.vm.activeResourceIndex = 0;
    wrapper.vm.expanded['10:flow:BLOCKED'] = true;
    await wrapper.vm.$nextTick();
    expect(wrapper.findAll('[data-testid="messaging-flow-row"]')).toHaveLength(
      1
    );
    expect(wrapper.find('[data-testid="messaging-flow-row"]').text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.CHIPS.NOT_PUBLISHED'
    );
  });

  it('toggles a resource exclusion from its visible row switch', async () => {
    const wrapper = await mountForm();
    wrapper.vm.activeResourceIndex = 1;
    wrapper.vm.expanded['10:template:BLOCKED'] = true;
    await wrapper.vm.$nextTick();
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
    wrapper.vm.activeResourceIndex = 1;
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
    wrapper.vm.activeResourceIndex = 1;
    await wrapper.vm.$nextTick();
    await wrapper
      .findAll('button')
      .find(
        button => button.text() === 'CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.ASSIGN'
      )
      .trigger('click');
    await wrapper.get('input').setValue('73');
    wrapper.vm.paidTemplates = false;
    await wrapper.get('select').setValue('contact.name');
    await wrapper.get('[data-testid="dialog-confirm"]').trigger('click');

    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).toHaveBeenCalledWith(10, {
      name: 'pedido_listo',
      variable_bindings: { nombre: 'contact.name' },
    });
    expect(dispatch).toHaveBeenCalledWith('inboxes/get', { force: true });
    expect(wrapper.vm.capValue).toBe(73);
    expect(wrapper.vm.paidTemplates).toBe(false);
    expect(wrapper.find('[data-testid="unsaved"]').exists()).toBe(true);
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
    wrapper.vm.expanded['10:flow:BLOCKED'] = true;
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
    wrapper.vm.activeResourceIndex = 1;
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="messaging-template-row"] button[role="switch"]')
      .trigger('click');
    await flushPromises();

    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.CONFLICT');
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.RELOAD');
  });
  it('preserves a dirty draft across assistant refreshes and clears the hint after saving', async () => {
    const wrapper = await mountForm();
    expect(wrapper.find('[data-testid="unsaved"]').exists()).toBe(false);
    await wrapper.get('input').setValue('73');
    wrapper.vm.paidTemplates = false;
    await wrapper.setProps({
      assistant: { ...wrapper.props('assistant'), updated_at: 99 },
    });
    expect(wrapper.vm.capValue).toBe(73);
    expect(wrapper.vm.paidTemplates).toBe(false);
    expect(wrapper.find('[data-testid="unsaved"]').exists()).toBe(true);
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    await flushPromises();
    expect(AccountAPI.update).toHaveBeenCalledWith('', {
      captain_template_daily_cap: 73,
    });
    expect(
      AssistantAPI.update.mock.lastCall[1].config.allow_paid_templates
    ).toBe(false);
    expect(
      dispatch.mock.calls.filter(([name]) => name === 'captainAssistants/show')
    ).toHaveLength(1);
    expect(wrapper.find('[data-testid="unsaved"]').exists()).toBe(false);
  });

  it('renders a loading skeleton before showing the empty state', async () => {
    let resolve;
    AssistantAPI.show.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = await mountForm({ inboxes: [] });
    expect(wrapper.findAll('.animate-pulse')).toHaveLength(3);
    expect(wrapper.text()).not.toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.NO_INBOXES'
    );
    resolve({ data: {} });
    await flushPromises();
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.NO_INBOXES');
  });

  it('shows a load error instead of a misleading empty state', async () => {
    AssistantAPI.show.mockRejectedValueOnce(new Error('network'));
    const wrapper = await mountForm({ inboxes: [] });
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.LOAD_ERROR');
    expect(wrapper.text()).not.toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.NO_INBOXES'
    );
  });

  it('keeps the eye available for an agent while disabling edits', async () => {
    adminAccess.value = false;
    const wrapper = await mountForm();
    wrapper.vm.activeResourceIndex = 1;
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.READ_ONLY');
    expect(
      wrapper.get('[data-testid="messaging-save"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper
        .get('[data-testid="messaging-template-row"] button[role="switch"]')
        .attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-testid="resource-preview"]').trigger('click');
    expect(templatePreviewOpen).toHaveBeenCalled();
  });

  it('hides the resource tabs when the number is off', async () => {
    const wrapper = await mountForm();
    wrapper.vm.permissionEntries[10].enabled = false;
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-testid="resource-tabs"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.OFF');
  });

  it.each([
    ['available', 'READY', null, true],
    ['excluded', 'READY', null, true],
    ['marketing_off', 'PERMISSION', null, true],
    ['new', 'PERMISSION', 'NEW', true],
    ['changed', 'PERMISSION', 'CHANGED', true],
    ['needs_review', 'PERMISSION', 'LINK', true],
    ['needs_data', 'PERMISSION', 'NEEDS_DATA', false],
    ['unsupported', 'BLOCKED', 'UNSUPPORTED', false],
    ['pending', 'BLOCKED', null, false],
    ['rejected', 'BLOCKED', null, false],
  ])(
    'renders the %s state in its prescribed group',
    async (state, group, chip, hasSwitch) => {
      const wrapper = await mountForm({
        assistant: {
          envios: {
            template_cap: { cap: 50, used: 0 },
            inboxes: [
              {
                inbox_id: 10,
                waba_id: 'waba-10',
                resources: [
                  {
                    resource: {
                      name: 'pedido_listo',
                      language: 'es',
                      category:
                        state === 'marketing_off' ? 'MARKETING' : 'UTILITY',
                    },
                    state,
                  },
                ],
              },
            ],
          },
        },
      });
      if (group === 'PERMISSION')
        expect(wrapper.vm.activeResourceIndex).toBe(1);
      wrapper.vm.activeResourceIndex = 1;
      if (group === 'BLOCKED') {
        expect(wrapper.find('[data-testid="template-BLOCKED"]').exists()).toBe(
          false
        );
        wrapper.vm.expanded['10:template:BLOCKED'] = true;
      }
      await wrapper.vm.$nextTick();
      const row = wrapper.get(`[data-testid="template-${group}"] li`);
      expect(row.find('button[role="switch"]').exists()).toBe(hasSwitch);
      if (chip) expect(row.text()).toContain(`CHIPS.${chip}`);
      expect(wrapper.vm.resourceTabs[1].count).toBe(1);
      expect(wrapper.vm.resourceTabs[1].attention).toBe(group === 'PERMISSION');
    }
  );

  it('blocks template edits on RED quality while keeping saved selections', async () => {
    const wrapper = await mountForm({
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 0 },
          inboxes: [
            {
              inbox_id: 10,
              waba_id: 'waba-10',
              channel: { quality_rating: 'RED' },
              resources: [
                {
                  resource: {
                    name: 'pedido_listo',
                    language: 'es',
                    category: 'UTILITY',
                  },
                  state: 'unavailable',
                },
              ],
            },
          ],
        },
      },
    });
    wrapper.vm.activeResourceIndex = 1;
    await wrapper.vm.$nextTick();
    const row = wrapper.get('[data-testid="messaging-template-row"]');
    expect(row.text()).toContain('CHIPS.QUALITY');
    expect(
      row.get('button[role="switch"]').attributes('disabled')
    ).toBeDefined();
    expect(row.get('button[role="switch"]').attributes('aria-checked')).toBe(
      'true'
    );
  });
  it.each(['', '-1', '1.5', '10001'])('rejects invalid cap %s', async value => {
    const wrapper = await mountForm();
    await wrapper.get('input').setValue(value);
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.CAP.INVALID');
    expect(
      wrapper.get('[data-testid="messaging-save"]').attributes('disabled')
    ).toBeDefined();
  });

  it('saves exclusions, several queued permissions and the cap in one ordered operation', async () => {
    AssistantAPI.allowResource.mockResolvedValue({
      data: { config: { messaging: { revision: 7 } } },
    });
    const wrapper = await mountForm({
      assistant: {
        envios: {
          template_cap: { cap: 50, used: 0 },
          inboxes: [
            {
              inbox_id: 10,
              waba_id: 'waba-10',
              resources: [
                {
                  resource: {
                    name: 'pedido_listo',
                    language: 'es',
                    category: 'UTILITY',
                  },
                  state: 'available',
                },
                {
                  resource: {
                    name: 'new_template',
                    language: 'es',
                    category: 'UTILITY',
                  },
                  state: 'new',
                },
                {
                  resource: {
                    name: 'changed_template',
                    language: 'es',
                    category: 'UTILITY',
                  },
                  state: 'changed',
                },
              ],
            },
          ],
        },
      },
    });
    await wrapper.get('input').setValue('73');
    await wrapper
      .get('[data-testid="template-READY"] button[role="switch"]')
      .trigger('click');
    const permissionSwitches = wrapper.findAll(
      '[data-testid="template-PERMISSION"] button[role="switch"]'
    );
    await permissionSwitches[0].trigger('click');
    await permissionSwitches[1].trigger('click');
    expect(AssistantAPI.allowResource).not.toHaveBeenCalled();
    expect(
      wrapper.findAll('[data-testid="template-PERMISSION"] li')
    ).toHaveLength(2);
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    await flushPromises();
    expect(
      AssistantAPI.update.mock.lastCall[1].config.messaging.inboxes[0].excluded
        .templates
    ).toEqual(['waba-10:pedido_listo|es']);
    expect(AccountAPI.update).toHaveBeenCalledWith('', {
      captain_template_daily_cap: 73,
    });
    expect(AssistantAPI.allowResource).toHaveBeenCalledTimes(2);
    expect(AssistantAPI.allowResource.mock.calls[0][0].revision).toBe(4);
    expect(AssistantAPI.allowResource.mock.calls[1][0].revision).toBe(7);
    expect(AssistantAPI.update.mock.invocationCallOrder[0]).toBeLessThan(
      AssistantAPI.allowResource.mock.invocationCallOrder[0]
    );
    expect(
      dispatch.mock.calls.filter(([name]) => name === 'captainAssistants/show')
    ).toHaveLength(1);
    expect(wrapper.find('[data-testid="unsaved"]').exists()).toBe(false);
  });
  it('keeps the complete permission queue if a later request fails', async () => {
    AssistantAPI.allowResource
      .mockResolvedValueOnce({
        data: { config: { messaging: { revision: 5 } } },
      })
      .mockRejectedValueOnce(new Error('network'));
    const wrapper = await mountForm({
      assistant: {
        envios: {
          inboxes: [
            {
              inbox_id: 10,
              waba_id: 'waba-10',
              resources: ['one', 'two'].map(name => ({
                resource: { name, language: 'es', category: 'UTILITY' },
                state: 'new',
              })),
            },
          ],
        },
      },
    });
    const switches = wrapper.findAll(
      '[data-testid="template-PERMISSION"] button[role="switch"]'
    );
    await switches[0].trigger('click');
    await switches[1].trigger('click');
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="unsaved"]').exists()).toBe(true);
    expect(Object.values(wrapper.vm.pendingAllows)).toHaveLength(2);
    expect(
      dispatch.mock.calls.filter(([name]) => name === 'captainAssistants/show')
    ).toHaveLength(0);
  });
});
