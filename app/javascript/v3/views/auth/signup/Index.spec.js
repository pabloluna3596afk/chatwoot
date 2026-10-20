import authEn from 'dashboard/i18n/locale/en/auth.json';
import authEs from 'dashboard/i18n/locale/es/auth.json';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import en from 'dashboard/i18n/locale/en/signup.json';
import es from 'dashboard/i18n/locale/es/signup.json';
import loginEn from 'dashboard/i18n/locale/en/login.json';
import loginEs from 'dashboard/i18n/locale/es/login.json';
import AuthSplitLayout from '../../../components/Auth/AuthSplitLayout.vue';
import Signup from './Index.vue';

describe('Signup page', () => {
  let wrapper;
  let router;
  let store;

  beforeEach(async () => {
    window.chatwootConfig = { allowedLoginMethods: ['email'] };
    store = createStore({
      getters: {
        'globalConfig/get': () => ({
          installationName: 'ChatHub',
          logo: '/logo.svg',
          logoDark: '/logo-dark.svg',
        }),
      },
    });
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/app/auth/signup', component: Signup },
        { path: '/app/login', component: { template: '<div />' } },
      ],
    });
    await router.push('/app/auth/signup');
    await router.isReady();
  });

  afterEach(() => {
    wrapper?.unmount();
    window.chatwootConfig = {};
  });

  it.each(['en', 'es'])(
    'renders the shared layout, existing two-field contract and login link in %s',
    async locale => {
      const messages = { en, es }[locale].REGISTER;
      const i18n = createI18n({
        legacy: false,
        locale,
        messages: {
          en: { ...en, ...loginEn, ...authEn },
          es: { ...es, ...loginEs, ...authEs },
        },
      });
      wrapper = mount(Signup, {
        global: { plugins: [store, router, i18n] },
      });
      expect(wrapper.getComponent(AuthSplitLayout).exists()).toBe(true);
      expect(wrapper.get('[data-testid="auth-marketing-title"]').text()).toBe(
        messages.MARKETING.TITLE
      );
      expect(wrapper.text()).toContain(messages.MARKETING.SUBTITLE);
      expect(wrapper.get('h1').text()).toBe(messages.TITLE);
      expect(wrapper.text()).toContain(messages.HAVE_AN_ACCOUNT);
      expect(wrapper.findAll('input')).toHaveLength(2);
      expect(wrapper.find('select').exists()).toBe(false);
      expect(wrapper.find('[style]').exists()).toBe(false);
      expect(wrapper.find('.border-t').exists()).toBe(false);
      expect(wrapper.get('input[type="email"]').attributes('aria-label')).toBe(
        messages.EMAIL.LABEL
      );
      expect(
        wrapper.get('input[type="password"]').attributes('aria-label')
      ).toBe(messages.PASSWORD.LABEL);
      wrapper.findAll('input').forEach(input => {
        expect(input.classes()).toEqual(
          expect.arrayContaining(['h-14', 'rounded-xl', 'reset-base'])
        );
        expect(input.attributes('placeholder')).toBeTruthy();
      });
      expect(
        wrapper.findAll('label').every(label => label.classes('sr-only'))
      ).toBe(true);
      const submit = wrapper.get('button[type="submit"]');
      expect(submit.text()).toBe(messages.SUBMIT);
      expect(submit.classes()).toEqual(
        expect.arrayContaining(['min-h-12', 'rounded-xl'])
      );
      expect(wrapper.get('p a[href$="/terms"]').exists()).toBe(true);
      const link = wrapper.get('a[href="/app/login"]');
      expect(link.text()).toBe(messages.SIGN_IN);
      await link.trigger('click');
      await flushPromises();
      expect(router.currentRoute.value.path).toBe('/app/login');
    }
  );
});
