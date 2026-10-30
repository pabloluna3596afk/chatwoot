import { flushPromises, mount } from '@vue/test-utils';
import AiUsageAPI from 'dashboard/api/aiUsage';
import ButtonV4 from 'next/button/Button.vue';
import UsageDashboard from '../UsageDashboard.vue';

vi.mock('dashboard/api/aiUsage', () => ({
  default: { get: vi.fn() },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => [key, values?.date].filter(Boolean).join(' '),
    locale: { value: 'en' },
  }),
}));

describe('Usage dashboard', () => {
  beforeEach(() => {
    AiUsageAPI.get.mockResolvedValue({
      data: { period_end: '2026-11-01T00:00:00Z', daily: [] },
    });
  });

  it('shows allowance progress with the 80 and 100 percent thresholds', async () => {
    const wrapper = mount(UsageDashboard, {
      props: {
        responseLimits: { consumed: 20, totalCount: 100 },
        copilotLimits: { consumed: 85, totalCount: 100 },
        internalLimits: { consumed: 100, totalCount: 100 },
      },
      global: { stubs: { ButtonV4: true } },
    });
    await flushPromises();

    const bars = wrapper.findAll('[role="progressbar"]');
    expect(bars.map(bar => bar.attributes('aria-valuenow'))).toEqual([
      '20',
      '85',
      '100',
    ]);
    expect(bars[0].find('rect').classes()).toContain('fill-n-blue-9');
    expect(bars[1].find('rect').classes()).toContain('fill-n-amber-9');
    expect(bars[2].find('rect').classes()).toContain('fill-n-ruby-9');
    wrapper.unmount();
  });

  it('explains shared, unlimited, and not included AI pools', async () => {
    AiUsageAPI.get.mockResolvedValueOnce({
      data: {
        daily: [],
        bag_modes: {
          captain_responses: 'unlimited',
          copilot: 'shared',
          internal: 'not_included',
        },
      },
    });
    const wrapper = mount(UsageDashboard, {
      global: { stubs: { ButtonV4: true } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain(
      'BILLING_SETTINGS.USAGE.BAG_MODES.UNLIMITED'
    );
    expect(wrapper.text()).toContain('BILLING_SETTINGS.USAGE.BAG_MODES.SHARED');
    expect(wrapper.text()).toContain(
      'BILLING_SETTINGS.USAGE.BAG_MODES.NOT_INCLUDED'
    );
    expect(wrapper.findAll('[role="progressbar"]')).toHaveLength(0);
    wrapper.unmount();
  });

  it('shows a clear empty state when the account has not used AI', async () => {
    const wrapper = mount(UsageDashboard, {
      global: { stubs: { ButtonV4: true } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('BILLING_SETTINGS.USAGE.EMPTY');
    wrapper.unmount();
  });

  it('formats period day labels consistently across time zones', async () => {
    AiUsageAPI.get.mockResolvedValueOnce({
      data: {
        period_end: '2026-11-01T00:00:00Z',
        daily: [
          { day: '2026-11-01', bucket: 'captain_responses', messages: 1 },
        ],
      },
    });
    const wrapper = mount(UsageDashboard, {
      props: { responseLimits: { consumed: 1, totalCount: 10 } },
      global: { stubs: { ButtonV4: true } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('Nov 1');
    expect(wrapper.text()).toContain('Nov 1, 2026');
    wrapper.unmount();
  });

  it('shows an error state when the usage endpoint is unavailable', async () => {
    AiUsageAPI.get.mockRejectedValueOnce(new Error('offline'));
    const wrapper = mount(UsageDashboard, {
      global: { stubs: { ButtonV4: true } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('BILLING_SETTINGS.USAGE.ERROR');
    wrapper.unmount();
  });

  it('shows the expiry notice and links to Billing', async () => {
    const wrapper = mount(UsageDashboard, {
      props: { expiredMessage: 'Your plan expired on Nov 1.' },
      global: { stubs: { ButtonV4: true } },
    });
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Your plan expired on Nov 1.'
    );
    await wrapper.findAllComponents(ButtonV4)[1].trigger('click');
    expect(wrapper.emitted('billing')).toBeTruthy();
    wrapper.unmount();
  });
});
