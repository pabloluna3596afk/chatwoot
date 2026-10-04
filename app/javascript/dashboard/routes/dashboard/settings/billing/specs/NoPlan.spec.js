import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';

import StripeBilling from '../Index.vue';

const currentAccount = ref({});
const isOnChatwootCloud = ref(false);
const fetchLimits = vi.fn();

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
  useStore: () => ({ dispatch: vi.fn() }),
}));

const mountBilling = () =>
  shallowMount(StripeBilling, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsLayout: {
          name: 'SettingsLayout',
          props: ['noRecordsFound', 'noRecordsMessage'],
          template: '<main />',
        },
      },
    },
  });

describe('Billing settings without a plan', () => {
  beforeEach(() => {
    currentAccount.value = { id: 1, limits: {} };
    fetchLimits.mockReset();
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
});
