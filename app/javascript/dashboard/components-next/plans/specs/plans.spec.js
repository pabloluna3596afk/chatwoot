import PlanStep from 'dashboard/routes/dashboard/onboarding/PlanStep.vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import { defineComponent } from 'vue';
import { readFileSync } from 'node:fs';
import { mount, flushPromises } from '@vue/test-utils';
import plans from 'dashboard/store/modules/plans';
import PlansAPI from 'dashboard/api/plans';
import en from 'dashboard/i18n/locale/en/planCatalog.json';
import es from 'dashboard/i18n/locale/es/planCatalog.json';
import enSettings from 'dashboard/i18n/locale/en/settings.json';
import esSettings from 'dashboard/i18n/locale/es/settings.json';
import PlanCatalog from '../PlanCatalog.vue';
import PlanPricingView from '../PlanPricingView.vue';
import PlanCard from '../PlanCard.vue';
import { catalog } from './fixtures';

vi.mock('dashboard/api/plans');

let store;
let router;
let i18n;
let wrapper;
beforeEach(async () => {
  PlansAPI.get.mockResolvedValue({ data: structuredClone(catalog) });
  store = createStore({
    modules: { plans },
    getters: {
      'accounts/getAccount': () => () => ({
        id: 1,
        limits: { plan: { id: 7, slug: 'trial' } },
      }),
      'globalConfig/get': () => ({
        logo: '/brand-assets/logo.svg',
        installationName: 'ChatHub',
      }),
    },
  });
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/accounts/:accountId', component: { template: '<div />' } },
    ],
  });
  await router.push('/accounts/1');
  i18n = createI18n({
    legacy: false,
    locale: 'es',
    messages: {
      en: { ...en, ...enSettings },
      es: { ...es, ...esSettings },
    },
  });
});
afterEach(() => wrapper?.unmount());

describe('plans store and catalog composable', () => {
  it('shares concurrent requests and caches within the account', async () => {
    let resolve;
    PlansAPI.get.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const first = store.dispatch('plans/load', { accountId: 1 });
    const second = store.dispatch('plans/load', { accountId: 1 });
    expect(PlansAPI.get).toHaveBeenCalledTimes(1);
    resolve({ data: catalog });
    await Promise.all([first, second]);
    await store.dispatch('plans/load', { accountId: 1 });
    expect(PlansAPI.get).toHaveBeenCalledTimes(1);
  });

  it('invalidates on account changes and discards late responses from a previous visit', async () => {
    let resolve;
    PlansAPI.get.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const old = store.dispatch('plans/load', { accountId: 1 });
    await store.dispatch('plans/load', { accountId: 2 });
    await store.dispatch('plans/load', { accountId: 1 });
    resolve({ data: [] });
    await old;
    expect(store.state.plans.records).toEqual(catalog);
    expect(PlansAPI.get.mock.calls).toEqual([[1], [2], [1]]);
  });

  it('shows errors and retries through the same API', async () => {
    PlansAPI.get.mockRejectedValueOnce(new Error('offline'));
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      es.PLAN_CATALOG.ERROR
    );
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(PlansAPI.get).toHaveBeenCalledTimes(2);
  });

  it('reacts to account navigation without displaying the previous catalog', async () => {
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    PlansAPI.get.mockReturnValueOnce(new Promise(() => {}));
    await router.push('/accounts/2');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Crecimiento');
    expect(wrapper.find('[data-testid="plans-loading"]').exists()).toBe(true);
    expect(PlansAPI.get).toHaveBeenLastCalledWith(2);
  });
});

describe('catalog presentation', () => {
  it('renders new plans, changed limits, features, states and sorting from API data', async () => {
    const extra = {
      ...catalog[1],
      id: 11,
      name: 'Expansión',
      display_order: -1,
      limits: { ...catalog[1].limits, monthly_responses: 12500 },
    };
    PlansAPI.get.mockResolvedValueOnce({
      data: [
        ...catalog,
        extra,
        { ...extra, id: 99, name: 'Hidden', state: 'hidden' },
      ],
    });
    wrapper = mount(PlanCatalog, {
      props: { currentPlanId: 7, canSelect: true },
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(
      wrapper.findAllComponents(PlanCard).map(card => card.props('plan').name)
    ).toEqual(['Expansión', 'Prueba', 'Crecimiento']);
    expect(wrapper.text()).toContain('12.500');
    expect(wrapper.text()).toContain('1 GB');
    expect(wrapper.text()).toContain('1 MB');
    expect(wrapper.text()).toContain('Bandejas');
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.LIMITS.copilot_responses);
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.LIMITS.internal_ai_calls);
    expect(wrapper.text()).toContain('Calendario y citas');
    expect(wrapper.text()).not.toContain('Hidden');
    expect(wrapper.find('.i-woot-captain').exists()).toBe(false);
    expect(wrapper.findAll('button:disabled')).toHaveLength(0);
    expect(wrapper.emitted('select')).toBeUndefined();
    expect(wrapper.emitted('continue')).toBeUndefined();
    expect(wrapper.emitted('requestUpgrade')).toBeUndefined();
    expect(PlansAPI.get).toHaveBeenCalledOnce();
  });

  it.each([
    [null, 'NO_CURRENT'],
    [100, 'UNLISTED'],
  ])('handles absent or unlisted current plan %s', async (id, key) => {
    wrapper = mount(PlanCatalog, {
      props: { currentPlanId: id },
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain(es.PLAN_CATALOG[key]);
    expect(wrapper.findAll('button:disabled')).toHaveLength(0);
  });

  it('renders loading then empty catalog without inventing values', async () => {
    PlansAPI.get.mockResolvedValueOnce({ data: [] });
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    expect(wrapper.find('[data-testid="plans-loading"]').exists()).toBe(true);
    await flushPromises();
    expect(wrapper.text()).toBe(es.PLAN_CATALOG.EMPTY);
    expect(wrapper.find('table').exists()).toBe(false);
  });

  it('hides zero and missing limits instead of rendering empty values or zeroes', async () => {
    PlansAPI.get.mockResolvedValueOnce({
      data: [{ ...catalog[0], limits: { storage_bytes: null } }],
    });
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('0 MB');
    expect(
      wrapper
        .findAll('tbody tr')
        .some(row => row.text().includes('Almacenamiento'))
    ).toBe(false);
    expect(wrapper.findAll('td').some(cell => cell.text().trim() === '0')).toBe(
      false
    );
  });

  it('shows catalog prices and inherited feature changes from plan data', async () => {
    wrapper = mount(PlanCatalog, {
      props: { currentPlanId: 7 },
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.FREE);
    expect(wrapper.text()).toContain('$119');
    expect(wrapper.text()).toContain('$1.190');
    expect(wrapper.text()).toContain(
      es.PLAN_CATALOG.INHERITS.replace('{plan}', 'Prueba')
    );
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.FEATURES.captain_tasks);
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.BASE_FEATURES);
    expect(
      wrapper.get('[data-testid="catalog-base-capabilities"]').text()
    ).toContain(es.PLAN_CATALOG.FEATURES.contacts_companies);
    expect(
      wrapper.findAll('[data-testid="catalog-base-capabilities"]')
    ).toHaveLength(1);
    expect(
      wrapper.findAll('[data-testid="base-capabilities-row"]')
    ).toHaveLength(1);
    expect(wrapper.get('[data-plan-id="7"]').text()).not.toContain(
      es.PLAN_CATALOG.FEATURES.contacts_companies
    );
    expect(wrapper.get('[data-plan-id="7"]').text()).toContain(
      es.PLAN_CATALOG.CURRENT
    );
    expect(wrapper.find('[data-plan-id="7"] button').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(es.PLAN_CATALOG.UNKNOWN);
    expect(wrapper.text()).not.toMatch(/PLAN_CATALOG\.(LIMITS|FEATURES)\./);
  });

  it('shows trial limits and Captain in the Prueba card without repeating base tools', async () => {
    wrapper = mount(PlanCatalog, {
      props: { currentPlanId: 7 },
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();

    const trialCard = wrapper.get('[data-plan-id="7"]');
    expect(trialCard.text()).toContain(
      es.PLAN_CATALOG.COUNTS.inboxes
        .split('|')[0]
        .replace('{count}', '1')
        .trim()
    );
    expect(trialCard.text()).toContain(
      es.PLAN_CATALOG.COUNTS.users.split('|')[0].replace('{count}', '1').trim()
    );
    expect(trialCard.text()).toContain(
      es.PLAN_CATALOG.COUNTS.assistants
        .split('|')[0]
        .replace('{count}', '1')
        .trim()
    );
    expect(trialCard.text()).toContain(
      es.PLAN_CATALOG.COUNTS.trial_responses
        .split('|')[1]
        .replace('{count}', '200')
        .trim()
    );
    expect(trialCard.text()).toContain('Almacenamiento: 1 MB');
    expect(trialCard.text()).toContain(
      es.PLAN_CATALOG.FEATURES.captain_integration
    );
    expect(trialCard.text()).not.toContain('200 respuestas de IA al mes');
    expect(trialCard.text()).not.toContain(
      es.PLAN_CATALOG.FEATURES.contacts_companies
    );
  });

  it('shows Gratis as the price regardless of the free plan name', async () => {
    PlansAPI.get.mockResolvedValueOnce({
      data: [{ ...catalog[0], name: es.PLAN_CATALOG.FREE }],
    });
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();

    const card = wrapper.get('[data-plan-id="7"]');
    expect(card.get('h3').text()).toBe(es.PLAN_CATALOG.FREE);
    expect(card.text().split(es.PLAN_CATALOG.FREE)).toHaveLength(3);
    expect(wrapper.get('thead th:nth-child(2)').text()).toBe(
      es.PLAN_CATALOG.FREE
    );
    expect(wrapper.get('tbody tr:first-child td').text()).toBe(
      es.PLAN_CATALOG.FREE
    );
    expect(card.text()).not.toContain(es.PLAN_CATALOG.BASE_FEATURES);
    expect(
      wrapper.get('[data-testid="catalog-base-capabilities"]').text()
    ).toContain(es.PLAN_CATALOG.BASE_FEATURES);
    expect(
      wrapper.findAll('[data-testid="base-capabilities-row"]')
    ).toHaveLength(1);
  });

  it('hides inheritance copy when the catalog has no feature differences', () => {
    const emptyFeaturePlans = catalog.map(plan => ({
      ...plan,
      feature_keys: [],
    }));
    const card = mount(PlanCard, {
      props: { plan: emptyFeaturePlans[1], plans: emptyFeaturePlans },
      global: { plugins: [i18n] },
    });

    expect(card.text()).not.toContain(
      es.PLAN_CATALOG.INHERITS.replace('{plan}', 'Prueba')
    );
  });

  it('calls out features removed from a higher plan', async () => {
    PlansAPI.get.mockResolvedValueOnce({
      data: [
        { ...catalog[0], feature_keys: ['captain_integration', 'automations'] },
        { ...catalog[1], feature_keys: ['captain_integration'] },
      ],
    });
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.REMOVED_FEATURES);
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.FEATURES.automations);
  });

  it('keeps every PLAN_CATALOG key used by the UI present in Spanish and English', () => {
    const files = [
      '../PlanCatalog.vue',
      '../PlanCard.vue',
      '../PlanComparisonTable.vue',
      '../PlanPricingView.vue',
      '../planPresentation.js',
    ];
    const source = files
      .map(file => readFileSync(new URL(file, import.meta.url), 'utf8'))
      .join('\n');
    const keys = [
      ...source.matchAll(
        /PLAN_CATALOG\.([A-Z][A-Z0-9_]*(?:\.[A-Z][A-Z0-9_]*)*)/g
      ),
    ].map(([, key]) => key);
    const hasPath = (object, path) =>
      path.split('.').every(part => {
        if (object == null || !Object.hasOwn(object, part)) return false;
        object = object[part];
        return true;
      });
    keys.forEach(key => {
      expect(hasPath(es.PLAN_CATALOG, key), `es PLAN_CATALOG.${key}`).toBe(
        true
      );
      expect(hasPath(en.PLAN_CATALOG, key), `en PLAN_CATALOG.${key}`).toBe(
        true
      );
    });
    catalog
      .flatMap(plan => plan.feature_keys)
      .forEach(feature => {
        expect(es.PLAN_CATALOG.FEATURES[feature]).toBeTruthy();
        expect(en.PLAN_CATALOG.FEATURES[feature]).toBeTruthy();
      });
    [...new Set(catalog.map(plan => plan.state))].forEach(state => {
      expect(es.PLAN_CATALOG.STATES[state]).toBeTruthy();
      expect(en.PLAN_CATALOG.STATES[state]).toBeTruthy();
    });
    [...new Set(catalog.flatMap(plan => Object.keys(plan.limits)))].forEach(
      limit => {
        expect(es.PLAN_CATALOG.LIMITS[limit]).toBeTruthy();
        expect(en.PLAN_CATALOG.LIMITS[limit]).toBeTruthy();
      }
    );
    ['MB', 'GB'].forEach(unit => {
      expect(es.PLAN_CATALOG[unit]).toBeTruthy();
      expect(en.PLAN_CATALOG[unit]).toBeTruthy();
    });
    [
      'inboxes',
      'assistants',
      'monthly_responses',
      'trial_responses',
      'users',
    ].forEach(key => {
      expect(es.PLAN_CATALOG.COUNTS[key]).toBeTruthy();
      expect(en.PLAN_CATALOG.COUNTS[key]).toBeTruthy();
    });
    const translationPaths = object =>
      Object.entries(object).flatMap(([key, value]) =>
        value && typeof value === 'object'
          ? translationPaths(value).map(path => `${key}.${path}`)
          : [key]
      );
    expect(translationPaths(es.PLAN_CATALOG).sort()).toEqual(
      translationPaths(en.PLAN_CATALOG).sort()
    );
    catalog[0].base_feature_keys.forEach(key => {
      expect(en.PLAN_CATALOG.FEATURES[key]).not.toMatch(/[áéíóúñ¿¡]/i);
      expect(en.PLAN_CATALOG.FEATURES[key]).not.toBe(
        es.PLAN_CATALOG.FEATURES[key]
      );
    });
    ['1', '2', '3', '4'].forEach(step => {
      expect(es.PLAN_CATALOG.QUESTIONS[step]).toBeTruthy();
      expect(en.PLAN_CATALOG.QUESTIONS[step]).toBeTruthy();
    });
  });

  it('shows current, upcoming, unavailable-to-user and purchasable plan actions clearly', async () => {
    wrapper = mount(PlanCard, {
      props: { plan: catalog[0], currentPlanId: 'trial', canSelect: true },
      global: { plugins: [i18n] },
    });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.CURRENT);

    await wrapper.setProps({
      currentPlanId: null,
      plan: { ...catalog[0], state: 'available' },
      canPurchase: false,
    });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(es.PLAN_CATALOG.MANAGE_PLAN_NOTE);

    await wrapper.setProps({
      plan: { ...catalog[0], state: 'coming_soon' },
    });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.STATES.coming_soon);
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.COMING_SOON_NOTE);

    await wrapper.setProps({
      plan: { ...catalog[1], state: 'available' },
      canPurchase: false,
    });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.MANAGE_PLAN_NOTE);

    await wrapper.setProps({
      plan: { ...catalog[1], state: 'available' },
      canPurchase: true,
    });
    expect(wrapper.get('button').attributes('disabled')).toBeUndefined();
    expect(wrapper.get('button').text()).toBe(esSettings.PAYPHONE.CHOOSE);
  });

  it('routes an available paid plan through the Payphone selection action', async () => {
    const paidPlan = { ...catalog[1], state: 'available' };
    wrapper = mount(PlanCard, {
      props: { plan: paidPlan, canSelect: true, canPurchase: true },
      global: { plugins: [i18n] },
    });

    expect(wrapper.get('button').text()).toBe(esSettings.PAYPHONE.CHOOSE);
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('select')).toEqual([[paidPlan.id]]);
    expect(wrapper.emitted('continue')).toEqual([[paidPlan.id]]);
  });

  it('does not offer a purchase button on the current plan', () => {
    const paidPlan = { ...catalog[1], state: 'available' };
    wrapper = mount(PlanCard, {
      props: {
        plan: paidPlan,
        currentPlanId: paidPlan.id,
        canSelect: true,
        canPurchase: true,
      },
      global: { plugins: [i18n] },
    });

    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).toContain(es.PLAN_CATALOG.CURRENT);
  });

  it('keeps translation keys in parity and formats English numbers', async () => {
    expect(Object.keys(en.PLAN_CATALOG).sort()).toEqual(
      Object.keys(es.PLAN_CATALOG).sort()
    );
    i18n.global.locale.value = 'en';
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Inboxes');
    expect(wrapper.text()).toContain('3,000');
  });
});

describe('comparison overlay', () => {
  it('focuses close, traps Tab both ways, locks background, closes on Esc and restores focus', async () => {
    const Harness = defineComponent({
      components: { PlanPricingView },
      data: () => ({ open: false }),
      template: `<div><button @click="open = true">{{ $t('PLAN_CATALOG.COMPARE') }}</button><PlanPricingView v-if="open" :current-plan-id="7" can-select @close="open = false" /></div>`,
    });
    wrapper = mount(Harness, {
      attachTo: document.body,
      global: { plugins: [store, router, i18n] },
    });
    const trigger = wrapper.get('button');
    trigger.element.focus();
    await trigger.trigger('click');
    await flushPromises();
    const dialog = document.querySelector('[role="dialog"]');
    const controls = [
      ...dialog.querySelectorAll('button:not(:disabled), [tabindex="0"]'),
    ];
    expect(document.activeElement).toBe(controls[0]);
    expect(wrapper.element.parentElement.inert).toBe(true);
    expect(document.body.style.overflow).toBe('hidden');
    controls[0].dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'Tab',
        shiftKey: true,
        bubbles: true,
      })
    );
    expect(document.activeElement).toBe(controls.at(-1));
    controls
      .at(-1)
      .dispatchEvent(
        new KeyboardEvent('keydown', { key: 'Tab', bubbles: true })
      );
    expect(document.activeElement).toBe(controls[0]);
    dialog.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    await flushPromises();
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(wrapper.element.parentElement.inert).toBeFalsy();
    expect(document.activeElement).toBe(trigger.element);
    expect(document.body.style.overflow).not.toBe('hidden');
  });

  it('continues by closing the comparison after selecting a purchasable plan', async () => {
    PlansAPI.get.mockResolvedValueOnce({
      data: catalog.map(plan =>
        plan.id === 9 ? { ...plan, state: 'available' } : plan
      ),
    });
    wrapper = mount(PlanPricingView, {
      props: {
        currentPlanId: 7,
        canSelect: true,
        canPurchase: true,
      },
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    document.querySelector('[data-plan-id="9"] button').click();
    await flushPromises();
    expect(wrapper.emitted('select')).toEqual([[9]]);
    expect(wrapper.emitted('continue')).toEqual([[9]]);
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(wrapper.emitted('requestUpgrade')).toBeUndefined();
  });
});

it('keeps onboarding completion on the simple screen and reuses its cached catalog', async () => {
  wrapper = mount(PlanStep, {
    attachTo: document.body,
    global: { plugins: [store, router, i18n] },
  });
  await flushPromises();
  expect(wrapper.text()).toContain(es.PLAN_CATALOG.BASE_FEATURES);
  expect(wrapper.text()).toContain(
    es.PLAN_CATALOG.FEATURES.captain_integration
  );
  const compare = wrapper
    .findAll('button')
    .find(button => button.text() === es.PLAN_CATALOG.COMPARE);
  await compare.trigger('click');
  await flushPromises();
  document.querySelector('[role="dialog"] button[aria-label="Cerrar"]').click();
  await flushPromises();
  expect(wrapper.emitted('continue')).toBeUndefined();
  expect(wrapper.findComponent(PlanPricingView).exists()).toBe(false);
  expect(PlansAPI.get).toHaveBeenCalledOnce();
  await wrapper.get('[data-testid="finish"]').trigger('click');
  expect(wrapper.emitted('continue')).toHaveLength(1);
});
