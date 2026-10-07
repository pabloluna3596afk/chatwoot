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
    publicationStatus: vi.fn(),
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

  it('marks edited published forms, including for agents', async () => {
    permissions.admin = false;
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: { payload: [{ ...flows[0], unpublished_changes: true }] },
    });
    const wrapper = await mountPanel();
    expect(wrapper.get('[data-testid="flow-unpublished-badge"]').text()).toBe(
      'WHATSAPP_FLOWS.META.UNPUBLISHED_CHANGES_BADGE'
    );
  });

  it('does not mark a current publication or a never published draft', async () => {
    const wrapper = await mountPanel();
    expect(
      wrapper.find('[data-testid="flow-unpublished-badge"]').exists()
    ).toBe(false);
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

  it('shows what Meta says about each flow, per WABA, to administrators', async () => {
    WhatsappFlowsAPI.publicationStatus.mockResolvedValue({
      data: {
        flow_id: 1,
        wabas: [
          { waba_id: '111', channel_id: 7, phone_number: '+593990001' },
          { waba_id: '222', channel_id: 8, phone_number: '+593990002' },
        ],
        publications: [{ waba_id: '111', status: 'published' }],
      },
    });
    const wrapper = await mountPanel();

    expect(WhatsappFlowsAPI.publicationStatus).toHaveBeenCalledWith(1);
    const badges = wrapper.findAll('[data-testid="flow-meta-badge"]');
    expect(badges.map(badge => badge.attributes('data-state'))).toEqual([
      'published',
      'none',
    ]);
  });

  it('shows no Meta badges to an agent, and does not ask Meta for them', async () => {
    permissions.admin = false;
    const wrapper = await mountPanel();

    expect(WhatsappFlowsAPI.publicationStatus).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="flow-row-meta"]').exists()).toBe(false);
  });

  it('keeps the list when the Meta status cannot be read', async () => {
    WhatsappFlowsAPI.publicationStatus.mockRejectedValue(new Error('x'));
    const wrapper = await mountPanel();

    expect(wrapper.findAll('[data-testid="flow-row"]')).toHaveLength(1);
    expect(wrapper.find('[data-testid="flow-meta"]').exists()).toBe(false);
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
