import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import AssistantMessagingForm from './AssistantMessagingForm.vue';
import AssistantAPI from 'dashboard/api/captain/assistant';
import CaptainInboxesAPI from 'dashboard/api/captain/inboxes';
import InboxesAPI from 'dashboard/api/inboxes';

const { linkedInboxes, inboxRecords, dispatch } = vi.hoisted(() => ({
  linkedInboxes: { value: [] },
  inboxRecords: { value: [] },
  dispatch: vi.fn(async () => ({})),
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
          props: ['modelValue', 'header', 'description'],
          emits: ['update:modelValue'],
          template: '<div><span>{{ header }}</span><slot /></div>',
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
            '<div data-testid="inbox-tabs">{{ JSON.stringify(tabs) }}</div>',
        },
        ComboBox: {
          props: ['options'],
          template:
            '<div data-testid="inbox-combo">{{ JSON.stringify(options) }}</div>',
        },
        Dialog: {
          props: ['title'],
          template: '<div><slot /></div>',
          methods: { open: vi.fn(), close: vi.fn() },
        },
        Input: {
          props: ['modelValue', 'label'],
          template: '<label>{{ label }}<input /></label>',
        },
        TextArea: { template: '<textarea />' },
        FlowPreviewDrawer: { template: '<div />', methods: { open: vi.fn() } },
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

  it('uses tabs for three mixed channels and only shows WhatsApp resources on WhatsApp', async () => {
    const inboxes = [
      whatsappInbox(10),
      { id: 11, name: 'Chat web', channel_type: 'Channel::WebWidget' },
      { id: 12, name: 'Correo', channel_type: 'Channel::Email' },
    ];
    const wrapper = await mountForm({ inboxes });
    wrapper.vm.selectTab({ inboxId: 11 });
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-testid="inbox-tabs"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.ENVIOS.ONLY_WHATSAPP');
    expect(wrapper.text()).toContain('Chat web');
  });

  it('uses a searchable inbox selector for ten inboxes', async () => {
    const inboxes = Array.from({ length: 10 }, (_, index) =>
      whatsappInbox(index + 1)
    );
    const wrapper = await mountForm({ inboxes });

    expect(wrapper.find('[data-testid="inbox-combo"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inbox-tabs"]').exists()).toBe(false);
  });

  it('saves the versioned messaging payload through the existing save action', async () => {
    const wrapper = await mountForm();
    await wrapper.get('[data-testid="messaging-save"]').trigger('click');

    const [payload] = wrapper.emitted('submit')[0];
    expect(payload.assistantPayload.config.messaging).toMatchObject({
      version: 2,
      revision: 4,
      inboxes: [expect.objectContaining({ inbox_id: 10, mode: 'auto' })],
    });
    expect(payload.dailyCap).toBe(50);
  });

  it('calls the server allow action for a newly approved resource', async () => {
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
                  state: 'new',
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
      .find(button => button.text() === 'CAPTAIN.ASSISTANTS.ENVIOS.ROW_ALLOW');
    await allow.trigger('click');

    expect(AssistantAPI.allowResource).toHaveBeenCalledWith({
      assistantId: 3,
      inboxId: 10,
      kind: 'template',
      key: 'waba-10:pedido_listo|es',
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
    wrapper.vm.bindingsDraft.nombre = 'contact.name';
    wrapper.vm.selectedRow = { resource: { name: 'pedido_listo' } };
    await wrapper.vm.saveAssignment();

    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).toHaveBeenCalledWith(10, {
      name: 'pedido_listo',
      variable_bindings: { nombre: 'contact.name' },
    });
    expect(dispatch).toHaveBeenCalledWith('captainAssistants/show', 3);
  });
});
