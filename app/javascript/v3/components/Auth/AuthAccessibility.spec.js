import { readFileSync } from 'node:fs';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import authEn from 'dashboard/i18n/locale/en/auth.json';
import authEs from 'dashboard/i18n/locale/es/auth.json';
import login from 'dashboard/i18n/locale/en/login.json';
import AuthButton from './AuthButton.vue';
import AuthChoiceCard from './AuthChoiceCard.vue';
import AuthField from './AuthField.vue';
import OnboardingShell from 'dashboard/routes/dashboard/onboarding/shared/OnboardingShell.vue';
import onboardingEn from 'dashboard/i18n/locale/en/onboarding.json';
import onboardingEs from 'dashboard/i18n/locale/es/onboarding.json';
import { createStore } from 'vuex';

const colorSource = readFileSync(
  'app/javascript/dashboard/assets/scss/_next-colors.scss',
  'utf8'
);
const palettes = colorSource
  .split('  .dark {')
  .map(source =>
    Object.fromEntries(
      [...source.matchAll(/--([\w-]+): ([\d ]+);/g)].map(([, token, value]) => [
        token,
        value.split(' ').map(Number),
      ])
    )
  );
const luminance = rgb =>
  rgb
    .map(value => value / 255)
    .map(value =>
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
    )
    .reduce(
      (sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index],
      0
    );
const contrast = (foreground, background) => {
  const values = [luminance(foreground), luminance(background)].sort(
    (a, b) => b - a
  );
  return (values[0] + 0.05) / (values[1] + 0.05);
};

describe('Onboarding accessibility', () => {
  let wrapper;
  afterEach(() => wrapper?.unmount());

  it.each(['en', 'es'])(
    'announces the named step and supports returning in %s',
    async locale => {
      const router = createRouter({
        history: createMemoryHistory(),
        routes: ['/previous', '/current'].map(path => ({
          path,
          component: { template: '<div />' },
        })),
      });
      await router.push('/current');
      const i18n = createI18n({
        legacy: false,
        locale,
        messages: {
          en: { ...authEn, ...onboardingEn },
          es: { ...authEs, ...onboardingEs },
        },
      });
      wrapper = mount(OnboardingShell, {
        attachTo: document.body,
        props: {
          title: 'Assistant',
          current: 3,
          backTo: { path: '/previous' },
          backDisabled: true,
        },
        global: {
          plugins: [
            router,
            i18n,
            createStore({
              getters: {
                'globalConfig/get': () => ({
                  logo: '/logo.svg',
                  installationName: 'ChatHub',
                }),
              },
            }),
          ],
        },
      });
      await flushPromises();
      expect(
        wrapper.get('[role="progressbar"]').attributes('aria-valuetext')
      ).toBe(i18n.global.t('ONBOARDING_LAYOUT.STEPS.ASSISTANT'));
      expect(wrapper.findAll('ol li')).toHaveLength(4);
      expect(wrapper.get('[aria-current="step"]').text()).toContain(
        i18n.global.t('ONBOARDING_LAYOUT.STEPS.ASSISTANT')
      );
      expect(wrapper.get('footer').classes()).toContain('shrink-0');
      expect(
        wrapper
          .get('[data-testid="onboarding-scroll-content"]')
          .find('footer')
          .exists()
      ).toBe(false);
      expect(document.activeElement).toBe(wrapper.get('h1').element);
      expect(wrapper.get('h1').attributes('tabindex')).toBe('-1');
      expect(wrapper.get('h1').classes()).toContain('outline-none');
      expect(
        wrapper
          .get('h1')
          .classes()
          .filter(name =>
            /^(?:focus(?:-visible)?:)?(?:outline|ring)(?:-|$)/.test(name)
          )
      ).toEqual(['outline-none']);
      await wrapper.get('a').trigger('click');
      await flushPromises();
      expect(router.currentRoute.value.path).toBe('/current');
      await wrapper.setProps({ backDisabled: false });
      await wrapper.get('a').trigger('click');
      await flushPromises();
      expect(router.currentRoute.value.path).toBe('/previous');
    }
  );

  it('associates errors and help with the field and preserves a visible password value', async () => {
    const i18n = createI18n({ legacy: false, messages: { en: login } });
    wrapper = mount(AuthField, {
      props: {
        id: 'password',
        label: 'Password',
        type: 'password',
        modelValue: 'Example!1',
        error: 'Check this password',
        describedby: 'requirements',
      },
      global: { plugins: [i18n] },
    });
    const input = wrapper.get('input');
    expect(wrapper.get('label').attributes('for')).toBe(input.attributes('id'));
    expect(input.attributes('aria-invalid')).toBe('true');
    expect(input.attributes('aria-describedby')).toBe(
      'requirements password-error'
    );
    expect(wrapper.get('#password-error[role="alert"]').text()).toBe(
      'Check this password'
    );
    await wrapper.get('button').trigger('click');
    expect(input.attributes('type')).toBe('text');
    expect(input.element.value).toBe('Example!1');
    expect(wrapper.get('button').attributes('aria-pressed')).toBe('true');
  });

  it('keeps loading actions named and disabled even if disabled is false', () => {
    wrapper = mount(AuthButton, {
      props: { loading: true, disabled: false },
      slots: { default: 'Continue' },
    });
    expect(wrapper.get('button').element.disabled).toBe(true);
    expect(wrapper.get('button').attributes('aria-busy')).toBe('true');
    expect(wrapper.text()).toBe('Continue');
    expect(wrapper.find('svg').exists()).toBe(true);
  });

  it('uses brand blue for primary actions and a solid border for secondary actions', async () => {
    wrapper = mount(AuthButton, { slots: { default: 'Continue' } });
    expect(wrapper.get('button').classes()).toContain('bg-n-brand');
    expect(wrapper.get('button').classes()).toContain('text-white');
    await wrapper.setProps({ variant: 'secondary' });
    expect(wrapper.get('button').classes()).toEqual(
      expect.arrayContaining(['border', 'border-solid', 'bg-n-solid-1'])
    );
  });

  it('prevents choosing a disabled option', async () => {
    wrapper = mount(AuthChoiceCard, {
      props: {
        name: 'tone',
        value: 'brief',
        modelValue: 'friendly',
        label: 'Brief',
        description: 'Short and direct',
        icon: 'i-lucide-zap',
        disabled: true,
      },
    });
    await wrapper.get('label').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it.each(['light', 'dark'])(
    'meets AA text and control contrast in %s mode',
    mode => {
      const colors = palettes[mode === 'dark' ? 1 : 0];
      const textPairs = [
        ['slate-12', 'solid-1'],
        ['slate-11', 'solid-1'],
        ['slate-11', 'solid-3'],
        ['slate-11', 'slate-3'],
        ['slate-11', 'blue-2'],
        ['slate-11', 'blue-3'],
        ['ruby-11', 'ruby-3'],
      ];
      textPairs.forEach(([foreground, background]) => {
        expect(
          contrast(colors[foreground], colors[background])
        ).toBeGreaterThanOrEqual(4.5);
      });
      expect(
        contrast(
          colors[mode === 'dark' ? 'slate-10' : 'slate-9'],
          colors['solid-3']
        )
      ).toBeGreaterThanOrEqual(3);
      expect(
        contrast(colors['blue-9'], colors['blue-2'])
      ).toBeGreaterThanOrEqual(3);
    }
  );
});
