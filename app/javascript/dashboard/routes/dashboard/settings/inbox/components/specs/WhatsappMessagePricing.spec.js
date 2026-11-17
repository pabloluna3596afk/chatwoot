import { flushPromises, mount } from '@vue/test-utils';
import WhatsappMessagePricing from '../WhatsappMessagePricing.vue';
import InboxHealthAPI from 'dashboard/api/inboxHealth';
import inboxMgmt from 'dashboard/i18n/locale/en/inboxMgmt.json';

vi.mock('dashboard/api/inboxHealth', () => ({
  default: { getMessagePricing: vi.fn() },
}));

const lookup = key =>
  key.split('.').reduce((node, part) => node?.[part], inboxMgmt);
const translate = (key, named = {}) =>
  String(lookup(key) ?? key).replace(
    /\{(\w+)\}/g,
    (match, name) => named[name] ?? match
  );

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, named) => translate(key, named),
    te: key => lookup(key) !== undefined,
    locale: { value: 'en' },
  }),
}));

const TabBarStub = {
  props: ['tabs', 'initialActiveTab', 'tabListLabel'],
  emits: ['tabChanged'],
  template:
    '<div><button v-for="tab in tabs" :key="tab.value" :data-month="tab.value" @click="$emit(\'tabChanged\', tab)">{{ tab.label }}</button></div>',
};
const ButtonStub = { template: '<button><slot /></button>' };
const BannerStub = { template: '<div data-test="partial"><slot /></div>' };

const monthSummary = (month, overrides = {}) => ({
  month,
  outgoing: 0,
  with_pricing: 0,
  app_sent: 0,
  categories: [],
  ...overrides,
});

const baseMonths = [
  monthSummary('2026-11'),
  monthSummary('2026-10'),
  monthSummary('2026-09'),
];

const mountComponent = async months => {
  InboxHealthAPI.getMessagePricing.mockResolvedValue({ data: { months } });
  const wrapper = mount(WhatsappMessagePricing, {
    props: { inboxId: 7 },
    global: {
      stubs: {
        TabBar: TabBarStub,
        Button: ButtonStub,
        Banner: BannerStub,
        Spinner: true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('WhatsappMessagePricing', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-11-17T12:00:00Z'));
    InboxHealthAPI.getMessagePricing.mockReset();
  });

  afterEach(() => vi.useRealTimers());

  it('shows the four figures and category table for the current month', async () => {
    const wrapper = await mountComponent([
      monthSummary('2026-11', {
        outgoing: 8,
        with_pricing: 3,
        app_sent: 2,
        categories: [{ category: 'service', billable: 2, free: 1 }],
      }),
      ...baseMonths.slice(1),
    ]);

    expect(wrapper.text()).toContain('Messages according to Meta');
    expect(wrapper.text()).toContain('Billable according to Meta');
    expect(wrapper.text()).toContain('Free according to Meta');
    expect(wrapper.text()).toContain('Sent from the phone app');
    expect(wrapper.text()).toContain('No data from Meta');
    expect(wrapper.text()).toContain('Replies within 24 hours');
    expect(wrapper.text()).toContain('3 of 6 · 50%');
  });

  it('changes the figures and table when the selected month changes, keeping coverage', async () => {
    const wrapper = await mountComponent([
      monthSummary('2026-11', {
        outgoing: 1,
        with_pricing: 1,
        categories: [{ category: 'service', billable: 1, free: 0 }],
      }),
      monthSummary('2026-10', {
        outgoing: 2,
        with_pricing: 2,
        categories: [{ category: 'marketing', billable: 2, free: 0 }],
      }),
      baseMonths[2],
    ]);
    const coverage = wrapper.find('h4').text();

    await wrapper.find('[data-month="2026-10"]').trigger('click');

    expect(wrapper.text()).toContain('Marketing templates');
    expect(wrapper.find('h4').text()).toBe(coverage);
    expect(wrapper.text()).toContain('2 of 2 · 100%');
  });

  it('excludes phone app echoes from no data and partial coverage', async () => {
    const wrapper = await mountComponent([
      monthSummary('2026-11', {
        outgoing: 2379,
        with_pricing: 58,
        app_sent: 2318,
        categories: [{ category: 'service', billable: 34, free: 24 }],
      }),
      ...baseMonths.slice(1),
    ]);

    expect(wrapper.text()).toContain('2,318');
    expect(wrapper.text()).toContain('3');
    expect(wrapper.text()).toContain('58 of 61 · 95%');
    expect(wrapper.find('[data-test="partial"]').exists()).toBe(false);
  });

  it('shows no partial banner and no category table when only phone app messages exist', async () => {
    const wrapper = await mountComponent([
      monthSummary('2026-11', { outgoing: 5, app_sent: 5 }),
      ...baseMonths.slice(1),
    ]);

    expect(wrapper.text()).toContain('0');
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.find('[data-test="partial"]').exists()).toBe(false);
  });

  it.each([40, 50])(
    'shows partial warning only below 50 percent (%s)',
    async percent => {
      const wrapper = await mountComponent([
        monthSummary('2026-11', {
          outgoing: 10,
          with_pricing: percent === 40 ? 4 : 5,
          categories: [
            { category: 'service', billable: percent === 40 ? 4 : 5, free: 0 },
          ],
        }),
        ...baseMonths.slice(1),
      ]);

      expect(wrapper.find('[data-test="partial"]').exists()).toBe(
        percent === 40
      );
    }
  );

  it('shows the empty month state without figures or a table', async () => {
    const wrapper = await mountComponent(baseMonths);

    expect(wrapper.text()).toContain(
      'There are no outgoing messages this month.'
    );
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.findAll('h4')).toHaveLength(1);
  });

  it('shows unknown category names unchanged', async () => {
    const wrapper = await mountComponent([
      monthSummary('2026-11', {
        outgoing: 1,
        with_pricing: 1,
        categories: [{ category: 'foo', billable: 1, free: 0 }],
      }),
      ...baseMonths.slice(1),
    ]);

    expect(wrapper.text()).toContain('foo');
  });

  it('shows an error and retries the request', async () => {
    InboxHealthAPI.getMessagePricing.mockRejectedValueOnce(
      new Error('Unavailable')
    );
    const wrapper = mount(WhatsappMessagePricing, {
      props: { inboxId: 7 },
      global: { stubs: { Button: ButtonStub, Spinner: true } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain(
      'The message summary could not be loaded.'
    );
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(InboxHealthAPI.getMessagePricing).toHaveBeenCalledTimes(2);
  });

  it('does not render currency symbols or amounts', async () => {
    const wrapper = await mountComponent([
      monthSummary('2026-11', {
        outgoing: 1,
        with_pricing: 1,
        categories: [{ category: 'service', billable: 1, free: 0 }],
      }),
      ...baseMonths.slice(1),
    ]);

    expect(wrapper.text()).not.toMatch(/\$|USD|€/u);
  });
});
