import { nextTick, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import UsageBreakdownCard from './UsageBreakdownCard.vue';

const mocks = vi.hoisted(() => ({
  getUsageBreakdown: vi.fn(),
  permissions: { isAdmin: true },
}));
const translate = (key, values) => {
  if (typeof values === 'number') return `${values} ${key}`;
  if (values) return `${key} ${Object.values(values).join(' ')}`;
  return key;
};

vi.mock('dashboard/api/captain/usageBreakdown', () => ({
  default: { getUsageBreakdown: mocks.getUsageBreakdown },
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(mocks.permissions.isAdmin) }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: ref('es'),
    t: translate,
  }),
}));

const breakdown = {
  period_start: '2026-11-01T00:00:00Z',
  period_end: '2026-12-01T00:00:00Z',
  buckets: {
    captain_responses: [
      {
        feature: 'reply',
        name: 'Respuestas automáticas',
        operations: 2,
        units: 7,
        last_used_at: '2026-11-04T12:00:00Z',
      },
      {
        feature: 'summary',
        name: 'Resumen',
        operations: 1,
        units: 3,
        last_used_at: '2026-11-03T12:00:00Z',
      },
    ],
    copilot: [
      {
        feature: 'copilot_reply',
        name: 'Copilot',
        operations: 3,
        units: 15,
        last_used_at: '2026-11-04T12:00:00Z',
        cost: 99,
        model: 'private-model',
        tokens: 999,
      },
    ],
    internal: [],
  },
};

const mountComponent = () =>
  mount(UsageBreakdownCard, { global: { mocks: { $t: translate } } });

describe('UsageBreakdownCard', () => {
  beforeEach(() => {
    mocks.permissions.isAdmin = true;
    mocks.getUsageBreakdown.mockReset();
    mocks.getUsageBreakdown.mockResolvedValue({ data: breakdown });
  });

  it('shows loading, empty, and error states with retry', async () => {
    let resolveRequest;
    mocks.getUsageBreakdown.mockReturnValue(
      new Promise(resolve => {
        resolveRequest = resolve;
      })
    );
    const loadingWrapper = mountComponent();
    await nextTick();
    expect(
      loadingWrapper
        .get('[aria-label="CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.LOADING"]')
        .exists()
    ).toBe(true);
    resolveRequest({ data: { ...breakdown, period_start: null } });
    await flushPromises();
    expect(loadingWrapper.text()).toContain('USAGE_BREAKDOWN.EMPTY');

    mocks.getUsageBreakdown.mockRejectedValueOnce(new Error('offline'));
    const errorWrapper = mountComponent();
    await flushPromises();
    expect(errorWrapper.text()).toContain('USAGE_BREAKDOWN.ERROR');
    await errorWrapper
      .get('button[aria-label="CAPTAIN.OVERVIEW.V2.USAGE_BREAKDOWN.RETRY"]')
      .trigger('click');
    await flushPromises();
    expect(mocks.getUsageBreakdown).toHaveBeenCalledTimes(3);
  });

  it('selects the largest bucket and switches rows and proportional bars', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.findAll('[role="tab"]')).toHaveLength(3);
    expect(wrapper.get('[data-testid="usage-period"]').text()).toContain(
      '2026'
    );
    expect(wrapper.get('[role="tab"][aria-selected="true"]').text()).toContain(
      'BILLING_SETTINGS.USAGE.BAGS.COPILOT'
    );
    expect(wrapper.text()).not.toContain('private-model');

    await wrapper.get('[role="tab"]:nth-child(1)').trigger('click');
    expect(wrapper.text()).toContain('Respuestas automáticas');
    expect(wrapper.text()).toContain('Resumen');
    const bars = wrapper.findAll('progress');
    expect(bars.map(bar => bar.element.value)).toEqual([7, 3]);
    expect(bars[0].element.max).toBe(7);
  });

  it('does not request the endpoint for non-admins', async () => {
    mocks.permissions.isAdmin = false;
    mountComponent();
    await nextTick();
    expect(mocks.getUsageBreakdown).not.toHaveBeenCalled();
  });

  it('does not render fields outside the usage breakdown contract', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).not.toMatch(/cost|model|token/i);
    expect(wrapper.text()).not.toContain('99');
    expect(wrapper.text()).not.toContain('999');
  });
});
