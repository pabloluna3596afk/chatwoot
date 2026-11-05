import { shallowMount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';

import StripeBilling from '../Index.vue';
import BillingTabs from '../components/BillingTabs.vue';

const currentAccount = ref({});
const isOnChatwootCloud = ref(false);
const fetchLimits = vi.fn();
const dispatch = vi.fn();
const route = reactive({ query: {} });
const replace = vi.fn();

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => route,
  useRouter: () => ({ replace }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount,
    isOnChatwootCloud,
  }),
}));

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({
    captainEnabled: ref(false),
    captainLimits: ref(null),
    responseLimits: ref(null),
    storageLimits: ref(null),
    fetchLimits,
    isFetchingLimits: ref(false),
  }),
}));

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ref({}),
  useStore: () => ({ dispatch }),
}));

const mountBilling = () =>
  shallowMount(StripeBilling, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        BillingCard: {
          template: '<section><slot name="action" /><slot /></section>',
        },
        ButtonV4: { template: '<button><slot /></button>' },
        SettingsLayout: {
          name: 'SettingsLayout',
          props: ['noRecordsFound', 'noRecordsMessage'],
          template:
            '<main><slot name="header" /><slot v-if="!noRecordsFound" name="body" /></main>',
        },
        BaseSettingsHeader: {
          template:
            '<header><slot name="tabs" /><slot name="actions" /></header>',
        },
      },
    },
  });

describe('Billing settings without a plan', () => {
  beforeEach(() => {
    currentAccount.value = { id: 1, limits: {} };
    fetchLimits.mockReset();
    dispatch.mockResolvedValue(undefined);
    route.query = {};
    replace.mockImplementation(async location => {
      route.query = location.query;
    });
  });

  it('tells a self-hosted account to ask its provider for a plan', async () => {
    isOnChatwootCloud.value = false;

    const wrapper = mountBilling();
    await flushPromises();
    const layout = wrapper.findComponent({ name: 'SettingsLayout' });

    expect(layout.props('noRecordsFound')).toBe(true);
    expect(layout.props('noRecordsMessage')).toBe(
      'BILLING_SETTINGS.NO_PLAN_ASSIGNED'
    );
  });

  it('keeps the "being configured" message on cloud', async () => {
    isOnChatwootCloud.value = true;

    const wrapper = mountBilling();
    await flushPromises();
    const layout = wrapper.findComponent({ name: 'SettingsLayout' });

    expect(layout.props('noRecordsMessage')).toBe(
      'BILLING_SETTINGS.NO_BILLING_USER'
    );
  });

  it('opens currency selection with visible tabs for a cloud account without a plan', async () => {
    isOnChatwootCloud.value = true;
    route.query = { source: 'settings' };
    dispatch.mockResolvedValue({
      currency_selection_required: true,
      currency_options: ['USD', 'BRL'],
    });

    const wrapper = mountBilling();
    await flushPromises();

    expect(replace).toHaveBeenCalledWith({
      query: { source: 'settings', tab: 'facturacion' },
    });
    expect(wrapper.findComponent(BillingTabs).exists()).toBe(true);
    expect(wrapper.find('#billing-panel-facturacion').exists()).toBe(true);
    expect(wrapper.findAll('button').map(button => button.text())).toEqual(
      expect.arrayContaining([
        'BILLING_SETTINGS.CURRENCY.OPTIONS.USD',
        'BILLING_SETTINGS.CURRENCY.OPTIONS.BRL',
      ])
    );
    expect(
      wrapper.findComponent({ name: 'SettingsLayout' }).props('noRecordsFound')
    ).toBe(false);
    expect(wrapper.findComponent({ name: 'UsageDashboard' }).exists()).toBe(
      false
    );
    wrapper.unmount();
  });
});
