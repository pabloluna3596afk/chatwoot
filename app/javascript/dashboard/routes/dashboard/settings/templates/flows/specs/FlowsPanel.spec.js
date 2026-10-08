import { flushPromises, mount } from '@vue/test-utils';
const openDetail = vi.fn();
const DetailStub = { template: '<div/>', methods: { open: openDetail } };
import FlowsPanel from '../FlowsPanel.vue';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import TemplatesIndex from '../../Index.vue';

vi.mock('../../TemplateCard.vue', () => ({ default: { template: '<div />' } }));
vi.mock('../../../SettingsLayout.vue', () => ({
  default: {
    template:
      '<div><slot name="header"/><slot name="preBody"/><slot name="body"/><slot/></div>',
  },
}));
vi.mock('../../../components/BaseSettingsHeader.vue', () => ({
  default: { template: '<div><slot name="tabs"/><slot name="actions"/></div>' },
}));

vi.mock('../../TemplateFormDrawer.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../../TemplatePreviewDrawer.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../../PresetsPanel.vue', () => ({ default: { template: '<div />' } }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue(true) }),
}));
vi.mock('dashboard/composables/useWhatsAppTemplateSync', () => ({
  useWhatsAppTemplateSync: () => ({
    whatsappInboxes: { value: [] },
    isSyncing: false,
    canSync: false,
    syncTemplates: vi.fn(),
  }),
}));

const { permissions, push } = vi.hoisted(() => ({
  permissions: { admin: true },
  push: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => ({ query: { tab: 'flows' } }),
}));
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
    duplicate: vi.fn(),
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
  it('shows a skeleton only until the first successful load', async () => {
    let resolve;
    const response = await WhatsappFlowsAPI.list();
    WhatsappFlowsAPI.list.mockClear();
    WhatsappFlowsAPI.list.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(FlowsPanel, {
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub, FlowPublicationPanel: DetailStub },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="flows-skeleton"]').exists()).toBe(true);
    resolve(response);
    await flushPromises();
    expect(wrapper.find('[data-testid="flows-skeleton"]').exists()).toBe(false);
    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
    wrapper.unmount();
  });

  it('keeps search, both filters and page across actual page tabs and refreshes silently', async () => {
    vi.useFakeTimers();
    const response = {
      data: {
        payload: flows,
        meta: { total_count: 24 },
        facets: {
          state: { all: 24, partial: 24 },
          category: { all: 24, SURVEY: 24 },
        },
      },
    };
    WhatsappFlowsAPI.list.mockResolvedValue(response);
    const wrapper = mount(TemplatesIndex, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          SettingsLayout: {
            template:
              '<div><slot name="header"/><slot name="preBody"/><slot name="body"/><slot/></div>',
          },
          BaseSettingsHeader: {
            template: '<div><slot name="tabs"/><slot name="actions"/></div>',
          },
          Dialog: DialogStub,
          FlowPublicationPanel: DetailStub,
        },
      },
    });
    await flushPromises();
    expect(WhatsappFlowsAPI.list).toHaveBeenCalledTimes(1);
    const panel = wrapper.findComponent(FlowsPanel);
    await panel.get('[data-testid="flows-toolbar"] input').setValue('Datos');
    const filters = panel.findAllComponents(FilterDropdown);
    filters[0].vm.$emit('update:modelValue', 'partial');
    filters[1].vm.$emit('update:modelValue', 'SURVEY');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    panel.findComponent(PaginationFooter).vm.$emit('update:currentPage', 2);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    wrapper
      .findComponent({ name: 'TabBar' })
      .vm.$emit('tabChanged', { key: 'templates' });
    await flushPromises();
    expect(wrapper.find('[data-testid="flows-panel"]').exists()).toBe(false);
    let resolve;
    WhatsappFlowsAPI.list.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    wrapper
      .findComponent({ name: 'TabBar' })
      .vm.$emit('tabChanged', { key: 'flows' });
    await flushPromises();
    expect(wrapper.findComponent(FlowsPanel).element).toBe(panel.element);
    expect(panel.get('[data-testid="flows-toolbar"] input').element.value).toBe(
      'Datos'
    );
    expect(filters.map(filter => filter.props('modelValue'))).toEqual([
      'partial',
      'SURVEY',
    ]);
    expect(panel.findComponent(PaginationFooter).props('currentPage')).toBe(2);
    expect(panel.findAll('tbody tr')).toHaveLength(1);
    expect(panel.find('[data-testid="flows-skeleton"]').exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(250);
    expect(panel.findAll('tbody tr')).toHaveLength(1);
    expect(panel.find('[data-testid="flows-skeleton"]').exists()).toBe(false);
    expect(WhatsappFlowsAPI.list).toHaveBeenLastCalledWith(
      {
        page: 2,
        per_page: 8,
        search: 'Datos',
        state: 'partial',
        category: 'SURVEY',
      },
      expect.any(Object)
    );
    resolve({
      data: {
        ...response.data,
        facets: {
          state: { all: 25, partial: 25 },
          category: { all: 25, SURVEY: 25 },
        },
      },
    });
    await flushPromises();
    expect(filters[0].props('options')[0].count).toBe(25);
    wrapper.unmount();
    vi.useRealTimers();
  });

  it('refreshes facet counts after publication updates', async () => {
    const wrapper = await mountPanel();
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: {
        payload: flows,
        meta: { total_count: 1 },
        facets: {
          state: { all: 1, published: 1, partial: 0 },
          category: { all: 1 },
        },
      },
    });
    wrapper.findComponent(DetailStub).vm.$emit('updated');
    await flushPromises();
    expect(WhatsappFlowsAPI.list).toHaveBeenCalledTimes(2);
    expect(
      wrapper
        .findAllComponents(FilterDropdown)[0]
        .props('options')
        .find(option => option.value === 'published').count
    ).toBe(1);
    wrapper.unmount();
  });

  it('loads newly created flows and their counts when returning from the editor', async () => {
    const wrapper = await mountPanel();
    wrapper.unmount();
    WhatsappFlowsAPI.list.mockResolvedValueOnce({
      data: {
        payload: [...flows, { ...flows[0], id: 2, name: 'Nuevo Flow' }],
        meta: { total_count: 2 },
        facets: {
          state: { all: 2, partial: 2 },
          category: { all: 2, LEAD_GENERATION: 2 },
        },
      },
    });
    const returned = await mountPanel();
    expect(returned.findAll('tbody tr')).toHaveLength(2);
    expect(returned.text()).toContain('Nuevo Flow');
    expect(
      returned.findAllComponents(FilterDropdown)[0].props('options')[0].count
    ).toBe(2);
    returned.unmount();
  });
  it('sends search, category and summary filters to the server and resets pagination', async () => {
    vi.useFakeTimers();
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: {
        payload: flows,
        meta: { total_count: 120 },
        facets: {
          state: { all: 120, partial: 108 },
          category: { all: 120, SURVEY: 12 },
        },
      },
    });
    const wrapper = await mountPanel();
    const filters = wrapper.findAllComponents(FilterDropdown);
    expect(
      filters[0].props('options').find(option => option.value === 'partial')
        .count
    ).toBe(108);
    expect(
      filters[1].props('options').find(option => option.value === 'SURVEY')
        .count
    ).toBe(12);
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: {
        payload: flows,
        meta: { total_count: 5 },
        facets: {
          state: { all: 9, partial: 5 },
          category: { all: 17, SURVEY: 5 },
        },
      },
    });
    wrapper.findComponent(PaginationFooter).vm.$emit('update:currentPage', 2);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(201);
    expect(WhatsappFlowsAPI.list).toHaveBeenLastCalledWith(
      { page: 2, per_page: 8 },
      expect.any(Object)
    );
    await wrapper.get('[data-testid="flows-toolbar"] input').setValue('Datos');
    wrapper
      .findAllComponents(FilterDropdown)[0]
      .vm.$emit('update:modelValue', 'partial');
    wrapper
      .findAllComponents(FilterDropdown)[1]
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
    expect(
      filters[0].props('options').find(option => option.value === 'all').count
    ).toBe(9);
    expect(
      filters[1].props('options').find(option => option.value === 'all').count
    ).toBe(17);
    expect(
      filters[1].props('options').find(option => option.value === 'OTHER').count
    ).toBe(0);
    wrapper.unmount();
    vi.useRealTimers();
  });
  beforeEach(() => {
    permissions.admin = true;
    push.mockReset();
    Object.values(WhatsappFlowsAPI).forEach(fn => fn.mockReset());
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: {
        payload: flows,
        meta: { total_count: 1 },
        facets: {
          state: { all: 1, partial: 1 },
          category: { all: 1, LEAD_GENERATION: 1 },
        },
      },
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
        facets: {
          state: { all: 1, partial: 1 },
          category: { all: 1, LEAD_GENERATION: 1 },
        },
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

    const rows = wrapper.findAll('tbody tr');
    expect(rows).toHaveLength(1);
    expect(rows[0].text()).toContain('Datos del cliente');
    expect(wrapper.text()).toContain('WHATSAPP_TEMPLATE_MGMT.TABLE.SCREENS');
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

    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
    expect(wrapper.find('[data-testid="flow-meta"]').exists()).toBe(false);
  });

  it('says there are no flows yet', async () => {
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: {
        payload: [],
        meta: { total_count: 0 },
        facets: { state: { all: 0 }, category: { all: 0 } },
      },
    });
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-testid="flows-empty"]').exists()).toBe(true);
  });

  it('lets only administrators create, edit and delete', async () => {
    permissions.admin = false;
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-testid="flow-new"]').exists()).toBe(false);
    expect(
      wrapper.get('[data-action="edit"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('[data-action="delete"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
  });

  it('"Nuevo flow" opens the full page of a new flow', async () => {
    const wrapper = mount(TemplatesIndex, {
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub, FlowPublicationPanel: DetailStub },
      },
    });
    await flushPromises();

    await wrapper.get('[data-testid="page-create"]').trigger('click');

    expect(push).toHaveBeenCalledWith({ name: 'settings_flow_new' });
    wrapper.unmount();
  });

  it('opens the editor when a row is clicked or receives Enter', async () => {
    const wrapper = await mountPanel();
    await wrapper.get('tbody tr').trigger('click');
    await wrapper.get('tbody tr').trigger('keydown', { key: 'Enter' });
    expect(push).toHaveBeenCalledTimes(2);
    expect(push).toHaveBeenCalledWith({
      name: 'settings_flow_edit',
      params: { flowId: 1 },
    });
    wrapper.unmount();
  });

  it('editing a flow opens its own full page', async () => {
    const wrapper = await mountPanel();

    await wrapper.get('[data-action="edit"]').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'settings_flow_edit',
      params: { flowId: 1 },
    });
  });

  it('duplicates only after confirmation and reloads the catalog', async () => {
    WhatsappFlowsAPI.duplicate.mockResolvedValue({ data: { id: 2 } });
    const wrapper = await mountPanel();
    await wrapper.get('[data-action="duplicate"]').trigger('click');
    expect(WhatsappFlowsAPI.duplicate).not.toHaveBeenCalled();
    wrapper.findAllComponents(DialogStub)[0].vm.$emit('confirm');
    await flushPromises();
    expect(WhatsappFlowsAPI.duplicate).toHaveBeenCalledWith(1);
    expect(WhatsappFlowsAPI.list).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('deletes a flow after asking', async () => {
    WhatsappFlowsAPI.remove.mockResolvedValue({});
    const wrapper = await mountPanel();
    WhatsappFlowsAPI.list.mockResolvedValue({
      data: {
        payload: [],
        meta: { total_count: 0 },
        facets: { state: { all: 0 }, category: { all: 0 } },
      },
    });

    await wrapper.get('[data-action="delete"]').trigger('click');
    wrapper.findAllComponents(DialogStub).at(-1).vm.$emit('confirm');
    await flushPromises();

    expect(WhatsappFlowsAPI.remove).toHaveBeenCalledWith(1);
    expect(WhatsappFlowsAPI.list).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-testid="flows-empty"]').exists()).toBe(true);
    expect(
      wrapper.findAllComponents(FilterDropdown)[0].props('options')[0].count
    ).toBe(0);
  });
});
