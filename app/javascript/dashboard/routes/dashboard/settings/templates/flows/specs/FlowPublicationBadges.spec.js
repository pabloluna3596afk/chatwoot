import { mount } from '@vue/test-utils';
import FlowPublicationBadges from '../FlowPublicationBadges.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const row = (state, extra = {}) => ({
  wabaId: '111',
  channelId: 7,
  phoneNumber: '+593990000001',
  state,
  errors: [],
  ...extra,
});

const mountBadges = props =>
  mount(FlowPublicationBadges, {
    props,
    global: {
      mocks: { $t: key => key },
      stubs: { Button: { template: '<button />' } },
    },
  });

const tone = state =>
  mountBadges({ rows: [row(state)] })
    .get('[data-testid="flow-meta-badge"]')
    .classes()
    .join(' ');

describe('FlowPublicationBadges', () => {
  it('shows a badge and the number per WABA', () => {
    const wrapper = mountBadges({
      rows: [
        row('published'),
        row('draft', { wabaId: '222', phoneNumber: '+2' }),
      ],
    });

    expect(wrapper.findAll('[data-testid="flow-meta-row"]')).toHaveLength(2);
    expect(wrapper.findAll('[data-testid="flow-meta-number"]')[1].text()).toBe(
      '+2'
    );
  });

  it('is green when published, amber as a draft in Meta, red on error, grey when never sent', () => {
    expect(tone('published')).toContain('bg-n-teal-3');
    expect(tone('draft')).toContain('bg-n-amber-3');
    expect(tone('error')).toContain('bg-n-ruby-3');
    expect(tone('blocked')).toContain('bg-n-ruby-3');
    expect(tone('throttled')).toContain('bg-n-ruby-3');
    expect(tone('none')).toContain('bg-n-alpha-2');
    expect(tone('deprecated')).toContain('line-through');
  });

  it('carries the small WhatsApp icon', () => {
    const wrapper = mountBadges({ rows: [row('published')] });

    expect(wrapper.find('.i-woot-whatsapp').exists()).toBe(true);
  });

  it('says "sending" for a draft while the flow is on its way', () => {
    const wrapper = mountBadges({ rows: [row('draft')], sending: true });

    expect(wrapper.get('[data-testid="flow-meta-badge"]').text()).toContain(
      'WHATSAPP_FLOWS.META.STATE.sending'
    );
  });

  it("shows Meta's errors (place and message) only when detailed", () => {
    const errors = [{ path: 'screens[0]', message: 'bad value' }];
    const rows = [row('error', { errors })];

    expect(
      mountBadges({ rows }).find('[data-testid="flow-meta-errors"]').exists()
    ).toBe(false);
    const detailed = mountBadges({ rows, detailed: true });
    const text = detailed.get('[data-testid="flow-meta-errors"]').text();
    expect(text).toContain('screens[0]');
    expect(text).toContain('bad value');
  });

  it("gives Meta's reason as a tooltip and an info hint in the list, not when detailed", () => {
    const errors = [
      { path: 'screens[0]', message: 'bad value' },
      { path: '', message: 'second' },
    ];
    const rows = [row('blocked', { errors })];

    const list = mountBadges({ rows });
    expect(
      list.get('[data-testid="flow-meta-badge"]').attributes('title')
    ).toBe('screens[0]: bad value\nsecond');
    expect(list.find('[data-testid="flow-meta-hint"]').exists()).toBe(true);

    const detailed = mountBadges({ rows, detailed: true });
    expect(
      detailed.get('[data-testid="flow-meta-badge"]').attributes('title')
    ).toBeUndefined();
    expect(detailed.find('[data-testid="flow-meta-hint"]').exists()).toBe(
      false
    );
    expect(
      mountBadges({ rows: [row('published')] })
        .find('[data-testid="flow-meta-hint"]')
        .exists()
    ).toBe(false);
  });

  it('offers "Reintentar" on errors, only when allowed, and says which WABA', async () => {
    const rows = [row('error', { wabaId: '222' })];

    expect(
      mountBadges({ rows }).find('[data-testid="flow-meta-retry"]').exists()
    ).toBe(false);
    expect(
      mountBadges({ rows: [row('published')], canRetry: true })
        .find('[data-testid="flow-meta-retry"]')
        .exists()
    ).toBe(false);

    const wrapper = mountBadges({ rows, canRetry: true });
    await wrapper.get('[data-testid="flow-meta-retry"]').trigger('click');
    expect(wrapper.emitted('retry')).toEqual([['222']]);
  });
});
