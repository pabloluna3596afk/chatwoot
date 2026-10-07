import { flushPromises, mount } from '@vue/test-utils';
const openDetail = vi.fn();
const DetailStub = { template: '<div/>', methods: { open: openDetail } };
import FlowsPanel from '../FlowsPanel.vue';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

const { permissions, push } = vi.hoisted(() => ({
  permissions: { admin: true },
  push: vi.fn(),
}));

vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false, locale: { value: 'en' } }),
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
    publication_summary: {
      state: 'partial',
      total: 120,
      published: 108,
      errors: 0,
    },
    updated_at: 1790000000,
  },
];

const mountPanel = async () => {
  const wrapper = mount(FlowsPanel, {
    global: {
      mocks: { $t: key => key },
      stubs: { Dialog: DialogStub, FlowPublicationPanel: DetailStub },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('FlowsPanel', () => {
  it('sends search, category and summary filters to the server and resets pagination', async () => {
    vi.useFakeTimers();
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: { payload: flows, meta: { total_count: 120 } },
    });
    const wrapper = await mountPanel();
    wrapper.findComponent(PaginationFooter).vm.$emit('update:currentPage', 2);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    expect(WhatsappFlowsAPI.list).toHaveBeenLastCalledWith(
      { page: 2, per_page: 8 },
      expect.any(Object)
    );
    await wrapper.get('[data-testid="flows-search"] input').setValue('Datos');
    wrapper
      .findAllComponents(ComboBox)[0]
      .vm.$emit('update:modelValue', 'partial');
    wrapper
      .findAllComponents(ComboBox)[1]
      .vm.$emit('update:modelValue', 'SURVEY');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    expect(WhatsappFlowsAPI.list).toHaveBeenLastCalledWith(
      {
        page: 1,
        per_page: 8,
        search: 'Datos',
        state: 'partial',
        category: 'SURVEY',
      },
      expect.any(Object)
    );
    wrapper.unmount();
    vi.useRealTimers();
  });
  beforeEach(() => {
    permissions.admin = true;
    push.mockReset();
    Object.values(WhatsappFlowsAPI).forEach(fn => fn.mockReset());
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: { payload: flows, meta: { total_count: 1 } },
    });
    WhatsappFlowsAPI.validate.mockResolvedValue({
      data: { valid: true, errors: [], flow_json: {} },
    });
  });

  it('marks edited published forms, including for agents', async () => {
    permissions.admin = false;
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: {
        payload: [{ ...flows[0], unpublished_changes: true }],
        meta: { total_count: 1 },
      },
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
    expect(wrapper.text()).toContain('WHATSAPP_FLOWS.LIST.SCREENS_HEADER');
    expect(rows[0].text()).toContain(
      'WHATSAPP_FLOWS.CATEGORIES.LEAD_GENERATION'
    );
  });

  it('shows one summary per Flow and opens WABA detail only on demand', async () => {
    const wrapper = await mountPanel();
    expect(WhatsappFlowsAPI.publicationStatus).not.toHaveBeenCalled();
    expect(
      wrapper.findAll('[data-testid="flow-publication-summary"]')
    ).toHaveLength(1);
    await wrapper
      .get('[data-testid="flow-publication-summary"]')
      .trigger('click');
    expect(openDetail).toHaveBeenCalledWith(flows[0]);
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
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: { payload: [], meta: { total_count: 0 } },
    });
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
