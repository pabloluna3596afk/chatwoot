import { flushPromises, mount } from '@vue/test-utils';
import FlowsPanel from '../FlowsPanel.vue';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';

const { permissions, push } = vi.hoisted(() => ({
  permissions: { admin: true },
  push: vi.fn(),
}));

vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => permissions.admin }),
}));
vi.mock('dashboard/api/whatsappFlows', () => ({
  default: {
    list: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    validate: vi.fn(),
  },
}));

const DialogStub = {
  template: '<div><slot /></div>',
  emits: ['confirm'],
  methods: { open: vi.fn(), close: vi.fn() },
};

const flows = [
  {
    id: 1,
    name: 'Datos del cliente',
    categories: ['LEAD_GENERATION'],
    screens: 2,
    updated_at: 1790000000,
  },
];

const mountPanel = async () => {
  const wrapper = mount(FlowsPanel, {
    global: { mocks: { $t: key => key }, stubs: { Dialog: DialogStub } },
  });
  await flushPromises();
  return wrapper;
};

describe('FlowsPanel', () => {
  beforeEach(() => {
    permissions.admin = true;
    push.mockReset();
    Object.values(WhatsappFlowsAPI).forEach(fn => fn.mockReset());
    WhatsappFlowsAPI.list.mockResolvedValue({ data: { payload: flows } });
    WhatsappFlowsAPI.validate.mockResolvedValue({
      data: { valid: true, errors: [], flow_json: {} },
    });
  });

  it('lists the flows with their screens and categories', async () => {
    const wrapper = await mountPanel();

    const rows = wrapper.findAll('[data-testid="flow-row"]');
    expect(rows).toHaveLength(1);
    expect(rows[0].text()).toContain('Datos del cliente');
    expect(rows[0].text()).toContain('WHATSAPP_FLOWS.LIST.SCREENS');
    expect(rows[0].text()).toContain(
      'WHATSAPP_FLOWS.CATEGORIES.LEAD_GENERATION'
    );
  });

  it('says there are no flows yet', async () => {
    WhatsappFlowsAPI.list.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-testid="flows-empty"]').exists()).toBe(true);
  });

  it('lets only administrators create, edit and delete', async () => {
    permissions.admin = false;
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-testid="flow-new"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="flow-edit"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="flow-delete"]').exists()).toBe(false);
    expect(wrapper.findAll('[data-testid="flow-row"]')).toHaveLength(1);
  });

  it('"Nuevo flow" opens the full page of a new flow', async () => {
    const wrapper = await mountPanel();

    await wrapper.get('[data-testid="flow-new"]').trigger('click');

    expect(push).toHaveBeenCalledWith({ name: 'settings_flow_new' });
  });

  it('editing a flow opens its own full page', async () => {
    const wrapper = await mountPanel();

    await wrapper.get('[data-testid="flow-edit"]').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'settings_flow_edit',
      params: { flowId: 1 },
    });
  });

  it('deletes a flow after asking', async () => {
    WhatsappFlowsAPI.remove.mockResolvedValue({});
    const wrapper = await mountPanel();

    await wrapper.get('[data-testid="flow-delete"]').trigger('click');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(WhatsappFlowsAPI.remove).toHaveBeenCalledWith(1);
    expect(WhatsappFlowsAPI.list).toHaveBeenCalledTimes(2);
  });
});
