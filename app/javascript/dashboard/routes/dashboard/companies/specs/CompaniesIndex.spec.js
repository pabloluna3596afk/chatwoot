import { flushPromises, mount } from '@vue/test-utils';
import CompaniesIndex from '../pages/CompaniesIndex.vue';

const store = vi.hoisted(() => ({
  records: [],
  fetching: false,
  get: vi.fn(),
  search: vi.fn(),
}));
const route = vi.hoisted(() => ({ params: { accountId: 1 }, query: {} }));
vi.mock('dashboard/stores/companies', () => ({
  useCompaniesStore: () => ({
    getCompaniesList: store.records,
    getMeta: { totalCount: store.records.length },
    getUIFlags: { fetchingList: store.fetching, creatingItem: false },
    get: store.get,
    search: store.search,
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    updateUISettings: vi.fn(),
    uiSettings: { value: {} },
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const company = { id: 5, name: 'Northwind', domain: 'northwind.test' };

const mountIndex = async () => {
  const wrapper = mount(CompaniesIndex, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        CompaniesListLayout: {
          name: 'CompaniesListLayout',
          template: '<div><slot /></div>',
          props: ['searchValue', 'headerTitle', 'currentPage', 'totalItems'],
          emits: ['search', 'update:currentPage', 'update:sort', 'create'],
        },
        CompaniesCard: {
          props: ['name'],
          template: '<article>{{ name }}</article>',
        },
        CompanyCreateDialog: true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('CompaniesIndex load errors', () => {
  beforeEach(() => {
    store.records = [];
    store.fetching = false;
    route.query = {};
    store.get.mockReset();
    store.search.mockReset();
  });

  it('shows a retry block after the initial request fails and recovers', async () => {
    store.get
      .mockRejectedValueOnce(new Error('Network unavailable'))
      .mockResolvedValueOnce();
    const wrapper = await mountIndex();

    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Network unavailable'
    );
    expect(wrapper.find('article').exists()).toBe(false);
    await wrapper.get('[role="alert"] button').trigger('click');
    await flushPromises();

    expect(store.get).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('preserves companies and request filters after refresh failure and retry', async () => {
    store.records = [company];
    route.query = { page: '3', search: 'North', sort: '-name' };
    store.search.mockResolvedValueOnce();
    const wrapper = await mountIndex();
    store.search
      .mockRejectedValueOnce(new Error('Refresh failed'))
      .mockResolvedValueOnce();
    wrapper
      .findComponent({ name: 'CompaniesListLayout' })
      .vm.$emit('update:currentPage', 3);
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).toContain('Refresh failed');
    expect(wrapper.get('article').text()).toBe('Northwind');
    await wrapper.get('[role="alert"] button').trigger('click');
    await flushPromises();

    expect(store.search).toHaveBeenCalledTimes(3);
    expect(store.search).toHaveBeenLastCalledWith({
      search: 'North',
      page: 3,
      sort: 'name',
    });
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('hides the initial loading placeholder from assistive technology', async () => {
    store.fetching = true;
    let finish;
    store.get.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(CompaniesIndex, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          CompaniesListLayout: { template: '<div><slot /></div>' },
          CompanyCreateDialog: true,
        },
      },
    });
    await flushPromises();

    expect(wrapper.get('[aria-hidden="true"][inert]').exists()).toBe(true);
    finish();
    await flushPromises();
    wrapper.unmount();
  });
});
