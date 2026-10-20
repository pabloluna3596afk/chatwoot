import { reactive } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import { mount, flushPromises } from '@vue/test-utils';
import BillingIndex from '../Index.vue';
import PlanPricingView from 'next/plans/PlanPricingView.vue';
import PlansAPI from 'dashboard/api/plans';
import plans from 'dashboard/store/modules/plans';
import { catalog } from 'next/plans/specs/fixtures';
import en from 'dashboard/i18n/locale/en/planCatalog.json';
import settings from 'dashboard/i18n/locale/en/settings.json';

vi.mock('dashboard/api/plans');
vi.mock('../components/PurchaseCreditsModal.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../../components/BaseSettingsHeader.vue', () => ({
  default: { template: '<header><slot name="actions" /></header>' },
}));
vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({
    captainEnabled: true,
    captainLimits: {},
    responseLimits: {
      customerConsumed: 12,
      customerTotalCount: 200,
      copilotConsumed: 3,
      copilotTotalCount: 100,
    },
    storageLimits: { consumed: 512, totalCount: 1048576 },
    fetchLimits: vi.fn(),
    isFetchingLimits: false,
  }),
}));

let wrapper;
afterEach(() => wrapper?.unmount());

it('opens the shared catalog with the current plan identity and preserves meters', async () => {
  const account = reactive({
    id: 1,
    custom_attributes: {},
    limits: {
      plan: { id: 7, slug: 'trial', name: 'Prueba' },
      agents: { consumed: 1, allowed: 2 },
      inboxes: { consumed: 1, allowed: 2 },
    },
  });
  const checkout = vi.fn();
  const store = createStore({
    modules: { plans },
    getters: {
      'accounts/getAccount': () => () => account,
      'accounts/getUIFlags': () => ({}),
      'globalConfig/get': () => ({
        logo: '/logo.svg',
        installationName: 'ChatHub',
      }),
      'globalConfig/isOnChatwootCloud': () => false,
    },
    actions: { 'accounts/checkout': checkout },
  });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/accounts/:accountId', component: { template: '<div />' } },
    ],
  });
  await router.push('/accounts/1');
  PlansAPI.get.mockResolvedValue({ data: catalog });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...en, ...settings } },
  });
  wrapper = mount(BillingIndex, {
    global: {
      plugins: [store, router, i18n],
      stubs: {
        PurchaseCreditsModal: true,
        BaseSettingsHeader: {
          template: '<header><slot name="actions" /></header>',
        },
      },
    },
  });
  await flushPromises();
  const meters = wrapper
    .findAllComponents({ name: 'BillingMeter' })
    .map(meter => meter.props());
  expect(meters.length).toBeGreaterThan(0);
  const compare = wrapper
    .findAll('button')
    .find(button => button.text() === 'Compare plans');
  await compare.trigger('click');
  await flushPromises();
  expect(wrapper.getComponent(PlanPricingView).props('currentPlanId')).toBe(7);
  expect(document.querySelector('[role="dialog"]').textContent).toContain(
    'Crecimiento'
  );
  expect(
    wrapper
      .findAllComponents({ name: 'BillingMeter' })
      .map(meter => meter.props())
  ).toEqual(meters);
  expect(checkout).not.toHaveBeenCalled();
  account.limits.plan = { slug: 'growth', name: 'Crecimiento' };
  await flushPromises();
  expect(wrapper.getComponent(PlanPricingView).props('currentPlanId')).toBe(
    'growth'
  );
});
