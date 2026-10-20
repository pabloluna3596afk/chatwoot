import PlanStep from 'dashboard/routes/dashboard/onboarding/PlanStep.vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import { defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import plans from 'dashboard/store/modules/plans';
import PlansAPI from 'dashboard/api/plans';
import en from 'dashboard/i18n/locale/en/planCatalog.json';
import es from 'dashboard/i18n/locale/es/planCatalog.json';
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
  i18n = createI18n({ legacy: false, locale: 'es', messages: { en, es } });
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
    expect(wrapper.text()).toContain('1 bandeja');
    expect(wrapper.text()).toContain('5 bandejas');
    expect(wrapper.text()).toContain('Calendario y citas');
    expect(wrapper.text()).not.toContain('Hidden');
    expect(wrapper.find('.i-woot-captain').exists()).toBe(true);
    expect(wrapper.findAll('button:disabled')).toHaveLength(2);
    await wrapper.get('[data-plan-id="7"] button').trigger('click');
    expect(wrapper.emitted('select')).toEqual([[7]]);
    expect(wrapper.emitted('continue')).toEqual([[7]]);
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
    expect(wrapper.findAll('button:disabled')).toHaveLength(2);
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

  it('does not render null/missing limits as zero', async () => {
    PlansAPI.get.mockResolvedValueOnce({
      data: [{ ...catalog[0], limits: { storage_bytes: null } }],
    });
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(wrapper.get('td').text()).toBe(es.PLAN_CATALOG.UNKNOWN);
    expect(wrapper.text()).not.toContain('0 MB');
  });

  it('only permits selection of an available current plan, including slug identity', async () => {
    wrapper = mount(PlanCard, {
      props: { plan: catalog[0], currentPlanId: 'trial', canSelect: true },
      global: { plugins: [i18n] },
    });
    expect(wrapper.get('button').attributes('disabled')).toBeUndefined();
    await wrapper.setProps({ currentPlanId: 9 });
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    await wrapper.setProps({
      currentPlanId: 7,
      plan: { ...catalog[0], state: 'coming_soon' },
    });
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
  });

  it('keeps translation keys in parity and formats English plurals', async () => {
    expect(Object.keys(en.PLAN_CATALOG)).toEqual(Object.keys(es.PLAN_CATALOG));
    i18n.global.locale.value = 'en';
    wrapper = mount(PlanCatalog, {
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('1 inbox');
    expect(wrapper.text()).toContain('5 inboxes');
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

  it('continues by closing the comparison without changing a subscription', async () => {
    wrapper = mount(PlanPricingView, {
      props: { currentPlanId: 7, canSelect: true },
      global: { plugins: [store, router, i18n] },
    });
    await flushPromises();
    document.querySelector('[data-plan-id="7"] button').click();
    await flushPromises();
    expect(wrapper.emitted('continue')).toEqual([[7]]);
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
  const compare = wrapper
    .findAll('button')
    .find(button => button.text() === es.PLAN_CATALOG.COMPARE);
  await compare.trigger('click');
  await flushPromises();
  document.querySelector('[role="dialog"] [data-plan-id="7"] button').click();
  await flushPromises();
  expect(wrapper.emitted('continue')).toBeUndefined();
  expect(wrapper.findComponent(PlanPricingView).exists()).toBe(false);
  expect(PlansAPI.get).toHaveBeenCalledOnce();
  await wrapper.get('[data-testid="finish"]').trigger('click');
  expect(wrapper.emitted('continue')).toHaveLength(1);
});
