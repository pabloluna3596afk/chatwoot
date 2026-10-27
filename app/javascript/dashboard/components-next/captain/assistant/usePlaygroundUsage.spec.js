import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import integrationsEn from 'dashboard/i18n/locale/en/integrations.json';
import integrationsEs from 'dashboard/i18n/locale/es/integrations.json';
import { usePlaygroundUsage } from './usePlaygroundUsage';

describe.each([
  ['en', integrationsEn],
  ['es', integrationsEs],
])('playground usage in %s', (locale, messages) => {
  const strings = messages.CAPTAIN.PLAYGROUND.USAGE;

  it.each([
    ['free', 0, 0, 50, 'FREE'],
    ['paid', 10, 3, 50, 'DAILY'],
    ['paid', 10, 10, 50, 'PLAN'],
    ['free', 0, 0, 0, 'responses_limit_reached'],
  ])(
    'renders %s plan, allowance %s, used %s, pool %s',
    (kind, total, used, pool, key) => {
      let usage;
      const wrapper = mount(
        {
          setup() {
            usage = usePlaygroundUsage();
            usage.update({
              test_usage: {
                plan_kind: kind,
                daily_total: total,
                daily_used: used,
                daily_remaining: total - used,
                uses_plan_pool: total === used,
                plan_remaining: pool,
              },
            });
            return usage;
          },
          template: '<p>{{ label }}</p>',
        },
        {
          global: {
            plugins: [
              createI18n({
                legacy: false,
                locale,
                messages: { [locale]: messages },
              }),
            ],
          },
        }
      );
      expect(wrapper.text()).toBe(
        strings[key]
          .replace('{count}', pool)
          .replace('{total}', total)
          .replace('{used}', used)
      );
      wrapper.unmount();
    }
  );

  it('translates rate exhaustion with Retry-After and accepts a retry result', () => {
    let usage;
    const wrapper = mount(
      {
        setup() {
          usage = usePlaygroundUsage();
          return usage;
        },
        template: '<p>{{ label }}</p>',
      },
      {
        global: {
          plugins: [
            createI18n({
              legacy: false,
              locale,
              messages: { [locale]: messages },
            }),
          ],
        },
      }
    );
    expect(
      usage.handleError({
        response: {
          status: 429,
          data: { error_code: 'playground_rate_limit' },
          headers: { 'retry-after': '30' },
        },
      })
    ).toBe(strings.playground_rate_limit.replace('{seconds}', '30'));
    usage.update({ test_usage: null });
    expect(usage.remaining.value).toBeNull();
    wrapper.unmount();
  });
});

it('shows the unlimited daily allowance in English', () => {
  let usage;
  const wrapper = mount(
    {
      setup() {
        usage = usePlaygroundUsage();
        usage.update({
          test_usage: {
            plan_kind: 'free',
            daily_total: null,
            daily_used: 3,
            daily_remaining: 1_000_000,
            uses_plan_pool: false,
            plan_remaining: 50,
          },
        });
        return usage;
      },
      template: '<p>{{ label }}</p>',
    },
    {
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: integrationsEn },
          }),
        ],
      },
    }
  );

  expect(wrapper.text()).toBe(
    integrationsEn.CAPTAIN.PLAYGROUND.USAGE.UNLIMITED_DAILY
  );
  wrapper.unmount();
});
