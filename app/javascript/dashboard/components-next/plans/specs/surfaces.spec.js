import { reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import PlansAPI from 'dashboard/api/plans';
import plans from 'dashboard/store/modules/plans';
import BasePaywallModal from 'dashboard/routes/dashboard/settings/components/BasePaywallModal.vue';
import UpgradePage from 'dashboard/routes/dashboard/upgrade/UpgradePage.vue';
import UsageCard from 'next/captain/pageComponents/overview/v2/UsageCard.vue';
import QuickLinks from 'next/captain/pageComponents/overview/QuickLinks.vue';
import ResponseBanner from 'next/captain/pageComponents/response/LimitBanner.vue';
import DocumentBanner from 'next/captain/pageComponents/document/LimitBanner.vue';
import CaptainPausedNotice from 'next/captain/CaptainPausedNotice.vue';
import PlanCompareButton from '../PlanCompareButton.vue';
import PlanPricingView from '../PlanPricingView.vue';
import { catalog } from './fixtures';
import en from 'dashboard/i18n/locale/en/planCatalog.json';
import es from 'dashboard/i18n/locale/es/planCatalog.json';
import integrations from 'dashboard/i18n/locale/en/integrations.json';
import generalSettings from 'dashboard/i18n/locale/en/generalSettings.json';

vi.mock('dashboard/api/plans');
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: true }),
}));
vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({
    responseLimits: ref({ consumed: 90, totalCount: 100 }),
    documentLimits: ref({ consumed: 5, totalCount: 5, currentAvailable: 0 }),
    fetchLimits: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkPermissions: roles => roles.includes('administrator'),
  }),
}));
let wrapper;
let account;
let session;
let router;
let store;
let options;
beforeEach(async () => {
  PlansAPI.get.mockResolvedValue({ data: structuredClone(catalog) });
  account = reactive({
    id: 1,
    created_at: '2020-01-01',
    billing_provider: null,
    limits: {
      plan: { id: 7 },
      conversation: { consumed: 100, allowed: 1 },
      non_web_inboxes: { consumed: 1, allowed: 1 },
      agents: { consumed: 1, allowed: 1 },
    },
  });
  session = reactive({ role: 'administrator', cloud: false });
  store = createStore({
    modules: { plans },
    getters: {
      getCurrentRole: () => session.role,
      getCurrentUser: () => ({ type: 'SuperAdmin' }),
      'accounts/getAccount': () => () => account,
      'captainAssistants/getRecords': () => [
        { id: 3, name: 'Sales', paused_reason: 'quota_exhausted' },
      ],
      'globalConfig/isOnChatwootCloud': () => session.cloud,
      'globalConfig/get': () => ({
        installationName: 'ChatHub',
        logo: '/logo.svg',
      }),
    },
    actions: { 'accounts/limits': vi.fn() },
  });
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/accounts/:accountId/:assistantId',
        component: { template: '<div />' },
      },
      {
        path: '/accounts/:accountId/billing',
        name: 'billing_settings_index',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push('/accounts/1/3');
  options = {
    global: {
      plugins: [
        store,
        router,
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...en, ...integrations, ...generalSettings }, es },
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      directives: {
        dompurifyHtml: el => {
          el.textContent = 'Feature availability';
        },
      },
      stubs: {
        ProgressMetric: {
          name: 'ProgressMetric',
          props: ['used', 'total'],
          template: '<div data-meter />',
        },
      },
    },
  };
});
afterEach(() => wrapper?.unmount());

it.each([
  [PlanCompareButton, {}],
  [UsageCard, {}],
  [QuickLinks, {}],
  [ResponseBanner, {}],
  [DocumentBanner, {}],
  [CaptainPausedNotice, {}],
  [
    BasePaywallModal,
    {
      featurePrefix: 'CAPTAIN',
      i18nKey: 'ENTERPRISE_PAYWALL',
      isSuperAdmin: true,
      requiredFeature: 'captain_integration',
    },
  ],
])(
  'opens the real shared catalog from %s without checkout',
  async (component, props) => {
    wrapper = mount(component, { ...options, props });
    const button = wrapper
      .findAll('button')
      .find(b => b.text() === 'Compare plans');
    expect(button).toBeDefined();
    expect(PlansAPI.get).not.toHaveBeenCalled();
    await button.trigger('click');
    await flushPromises();
    expect(wrapper.getComponent(PlanPricingView).props('currentPlanId')).toBe(
      7
    );
    expect(document.querySelector('[role="dialog"]').textContent).toContain(
      'Crecimiento'
    );
    expect(PlansAPI.get).toHaveBeenCalledExactlyOnceWith(1);
    expect(
      [...document.querySelectorAll('[data-plan-id] button')].every(
        planButton => planButton.disabled
      )
    ).toBe(true);
    expect(
      document.querySelectorAll('[role="dialog"] button:not(:disabled)').length
    ).toBeGreaterThan(0);
    await wrapper.getComponent(PlanPricingView).vm.$emit('close');
    await flushPromises();
    expect(document.querySelector('[role="dialog"]')).toBeNull();
  }
);

it.each(['agent', 'cloud', 'shopify'])(
  'does not offer or load the catalog for %s',
  async type => {
    session.role = type === 'agent' ? 'agent' : 'administrator';
    session.cloud = type === 'cloud';
    account.billing_provider = type === 'shopify' ? 'shopify' : null;
    wrapper = mount(PlanCompareButton, options);
    expect(wrapper.find('button').exists()).toBe(false);
    expect(PlansAPI.get).not.toHaveBeenCalled();
  }
);

it('closes the comparison on lost admin permission', async () => {
  wrapper = mount(PlanCompareButton, options);
  await wrapper.get('button').trigger('click');
  await flushPromises();
  session.role = 'agent';
  await flushPromises();
  expect(document.querySelector('[role="dialog"]')).toBeNull();
});

it('highlights only the catalog plans that include the requested feature', async () => {
  wrapper = mount(PlanCompareButton, {
    ...options,
    props: { requiredFeature: 'calendar_integration' },
  });
  await wrapper.get('button').trigger('click');
  await flushPromises();
  const card = document.querySelector('[data-plan-id="9"]');
  expect(card.classList.contains('ring-n-blue-9')).toBe(true);
  expect(
    [...card.querySelectorAll('li')].some(
      li =>
        li.textContent.includes('Calendar') &&
        li.classList.contains('bg-n-blue-3')
    )
  ).toBe(true);
  expect(wrapper.getComponent(PlanPricingView).props('requiredFeature')).toBe(
    'calendar_integration'
  );
  const featureRow = [...document.querySelectorAll('tbody tr')].find(row =>
    row.textContent.includes('Calendar')
  );
  expect(featureRow.classList.contains('bg-n-blue-3')).toBe(true);
});

it('reuses catalog error and retry from an entry surface', async () => {
  PlansAPI.get.mockRejectedValueOnce(new Error('offline'));
  wrapper = mount(PlanCompareButton, options);
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(document.querySelector('[role="alert"]').textContent).toContain(
    en.PLAN_CATALOG.ERROR
  );
  document.querySelector('[role="alert"] button').click();
  await flushPromises();
  expect(PlansAPI.get).toHaveBeenCalledTimes(2);
  expect(document.querySelector('[data-plan-id="9"]')).not.toBeNull();
});

it('keeps the existing billing action for the cloud paywall and hides it from agents', async () => {
  session.cloud = true;
  wrapper = mount(BasePaywallModal, {
    ...options,
    props: {
      featurePrefix: 'CAPTAIN',
      i18nKey: 'PAYWALL',
      isOnChatwootCloud: true,
    },
  });
  await wrapper.get('button').trigger('click');
  expect(wrapper.emitted('upgrade')).toHaveLength(1);
  expect(PlansAPI.get).not.toHaveBeenCalled();
  session.role = 'agent';
  await flushPromises();
  expect(wrapper.find('button').exists()).toBe(false);
});

it('does not expose the self-hosted paywall action without installation permission', () => {
  wrapper = mount(BasePaywallModal, {
    ...options,
    props: { featurePrefix: 'CAPTAIN', i18nKey: 'ENTERPRISE_PAYWALL' },
  });
  expect(wrapper.find('button').exists()).toBe(false);
});

it('keeps the cloud-only upgrade page navigation to billing', async () => {
  session.cloud = true;
  wrapper = mount(UpgradePage, options);
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(router.currentRoute.value.name).toBe('billing_settings_index');
  expect(PlansAPI.get).not.toHaveBeenCalled();
});

it('shows absent consumption as unknown and preserves genuine zero values', async () => {
  wrapper = mount(UsageCard, options);
  expect(wrapper.findAll('[data-meter]')).toHaveLength(0);
  expect(wrapper.text()).toContain(en.PLAN_CATALOG.UNKNOWN);
  await wrapper.setProps({ responseLimits: { consumed: 0, totalCount: 200 } });
  expect(wrapper.findAll('[data-meter]')).toHaveLength(1);
  expect(wrapper.findComponent({ name: 'ProgressMetric' }).props('used')).toBe(
    0
  );
});
