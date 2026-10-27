import { shallowMount } from '@vue/test-utils';
import BillingMeter from '../components/BillingMeter.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, params) => `${key} ${params?.date || ''}` }),
}));

const mountComponent = props =>
  shallowMount(BillingMeter, {
    props: {
      title: 'Copilot',
      consumed: 8,
      totalCount: 10,
      ...props,
    },
  });

describe('BillingMeter', () => {
  it('shows usage and the period reset date for a limited bag', () => {
    const wrapper = mountComponent({ periodEnd: '2026-10-26T12:00:00.000Z' });

    expect(wrapper.text()).toContain('8 / 10');
    expect(wrapper.text()).toContain(
      'BILLING_SETTINGS.CAPTAIN.RESETS_ON 26 Oct, 2026'
    );
  });

  it('does not show a reset date when a period is not available', () => {
    const wrapper = mountComponent();

    expect(wrapper.text()).not.toContain('RESETS_ON');
  });

  it('renders zero limits as exhausted without producing an invalid percentage', () => {
    const wrapper = mountComponent({ consumed: 0, totalCount: 0 });

    expect(wrapper.find('div[style]').attributes('style')).toContain('100%');
  });
});
