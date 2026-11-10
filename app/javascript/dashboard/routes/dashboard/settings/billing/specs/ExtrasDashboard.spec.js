import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ExtrasDashboard from '../ExtrasDashboard.vue';
import settingsEn from 'dashboard/i18n/locale/en/settings.json';
import settingsEs from 'dashboard/i18n/locale/es/settings.json';
import { formatBillingDate } from '../billingDate';

const packs = [
  {
    id: 1,
    bucket: 'captain_responses',
    units: 500,
    price_usd: 20,
    validity_days: 45,
  },
  {
    id: 2,
    bucket: 'captain_responses',
    units: 2000,
    price_usd: 64,
    validity_days: 75,
  },
  {
    id: 3,
    bucket: 'captain_responses',
    units: 5000,
    price_usd: 140,
    validity_days: 90,
  },
  { id: 4, bucket: 'copilot', units: 1000, price_usd: 5, validity_days: 30 },
  { id: 5, bucket: 'internal', units: 500, price_usd: 6, validity_days: 60 },
];
const catalog = {
  packs,
  monthly: { start: { agent: 18, bot: 35, inbox: 0, storage_100mb: 1 } },
};
const mountExtras = (props = {}, locale = 'en') =>
  mount(ExtrasDashboard, {
    props: { catalog, planSlug: 'start', ...props },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale,
          messages: { en: settingsEn, es: settingsEs },
        }),
      ],
    },
  });

describe.each(['en', 'es'])('Extras (%s)', locale => {
  it('shows one empty balance state linking to available packs', () => {
    const wrapper = mountExtras({}, locale);
    expect(wrapper.find('a[href="#extras-packs"]').exists()).toBe(true);
    expect(wrapper.findAll('article')).toHaveLength(5);
    wrapper.unmount();
  });

  it('shows active balances and formats the nearest expiry with the shared date helper', () => {
    const expiry = '2026-12-01T00:30:00Z';
    const wrapper = mountExtras(
      {
        captainLimits: {
          responses: { extra_available: 123, extra_next_expiry: expiry },
        },
      },
      locale
    );
    expect(wrapper.text()).toContain('123');
    expect(wrapper.text()).toContain(formatBillingDate(expiry, locale));
    expect(wrapper.find('a[href="#extras-packs"]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      locale === 'es' ? 'Sin saldo extra' : 'No extra balance'
    );
    wrapper.unmount();
  });

  it('derives unit prices, one best value per group and validity from the API', async () => {
    const wrapper = mountExtras({}, locale);
    const cards = wrapper.findAll('article');
    const bestLabel =
      locale === 'es' ? 'Menor precio por unidad' : 'Lowest price per unit';
    expect(cards.filter(card => card.text().includes(bestLabel))).toHaveLength(
      3
    );
    expect(cards[0].text()).not.toContain(bestLabel);
    expect(cards[2].text()).toContain(bestLabel);
    expect(cards[0].text()).toContain('USD 20');
    expect(cards[0].text()).toContain(
      new Intl.NumberFormat(locale, { minimumFractionDigits: 3 }).format(0.04)
    );
    expect(cards[0].text()).toContain('45');
    await wrapper.setProps({
      catalog: {
        ...catalog,
        packs: packs.map(pack => ({ ...pack, price_usd: 100 })),
      },
    });
    expect(wrapper.findAll('article')[0].text()).toContain('USD 100');
    wrapper.unmount();
  });

  it('shows only positive current-plan monthly prices and requests support', async () => {
    const wrapper = mountExtras({}, locale);
    expect(wrapper.text()).toContain('USD 18');
    expect(wrapper.text()).toContain('USD 35');
    expect(wrapper.text()).not.toMatch(/USD 0 \/ (month|mes)/);
    expect(wrapper.findAll('button')).toHaveLength(packs.length + 3);
    await Promise.all(
      wrapper.findAll('button').map(button => button.trigger('click'))
    );
    expect(wrapper.emitted('request')).toHaveLength(packs.length + 3);
    await wrapper.setProps({ planSlug: '' });
    expect(wrapper.findAll('button')).toHaveLength(packs.length);
    wrapper.unmount();
  });
});

it('distinguishes loading and catalog errors from empty balances', async () => {
  const wrapper = mountExtras({ catalog: null, isLoading: true });
  expect(wrapper.find('[role="status"]').exists()).toBe(true);
  expect(wrapper.findAll('button')).toHaveLength(0);
  await wrapper.setProps({ isLoading: false });
  expect(wrapper.find('[role="alert"]').text()).toContain(
    'Could not load extras'
  );
  wrapper.unmount();
});

it('keeps complete es/en extras key parity', () => {
  expect(Object.keys(settingsEn.BILLING_SETTINGS.EXTRAS)).toEqual(
    Object.keys(settingsEs.BILLING_SETTINGS.EXTRAS)
  );
  expect(Object.keys(settingsEn.BILLING_SETTINGS.EXTRAS.BAGS)).toEqual(
    Object.keys(settingsEs.BILLING_SETTINGS.EXTRAS.BAGS)
  );
  expect(Object.keys(settingsEn.BILLING_SETTINGS.EXTRAS.MONTHLY)).toEqual(
    Object.keys(settingsEs.BILLING_SETTINGS.EXTRAS.MONTHLY)
  );
});
