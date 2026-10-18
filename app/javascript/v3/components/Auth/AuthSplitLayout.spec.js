import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import loginHero from 'assets/images/auth/login-hero.png';
import AuthSplitLayout from './AuthSplitLayout.vue';

describe('AuthSplitLayout', () => {
  let wrapper;
  afterEach(() => wrapper?.unmount());

  it.each(['/logo-dark.svg', ''])(
    'shares the login photo, responsive column and branded logos with dark logo %j',
    logoDark => {
      const store = createStore({
        getters: {
          'globalConfig/get': () => ({
            installationName: 'ChatHub',
            logo: '/logo.svg',
            logoDark,
          }),
        },
      });
      wrapper = mount(AuthSplitLayout, {
        props: { title: 'Welcome to Chatwoot', subtitle: 'Your assistant' },
        slots: { default: '<form data-testid="auth-form" />' },
        global: { plugins: [store] },
      });

      expect(wrapper.get('main').classes()).toContain('dark:bg-n-background');
      const hero = wrapper.get('aside');
      expect(hero.classes()).toEqual(
        expect.arrayContaining(['hidden', 'lg:block', 'w-1/2'])
      );
      expect(hero.get('img[aria-hidden="true"]').attributes('src')).toBe(
        loginHero
      );
      expect(hero.get('img[alt="ChatHub"]').attributes('src')).toBe(
        logoDark || '/logo.svg'
      );
      expect(hero.get('h1').text()).toBe('Welcome to ChatHub');
      expect(hero.get('h1').classes()).toContain('text-white');
      expect(hero.get('p').classes()).toContain('text-white');
      expect(hero.text()).toContain('Your assistant');
      expect(hero.findAll('.bg-gradient-to-b, .bg-gradient-to-t')).toHaveLength(
        2
      );
      const column = wrapper.get('section');
      expect(column.classes()).toContain('lg:w-1/2');
      expect(column.get('.max-w-\\[30rem\\]').exists()).toBe(true);
      const mobileLogo = column.get('.lg\\:hidden');
      expect(mobileLogo.get('img.dark\\:hidden').attributes('src')).toBe(
        '/logo.svg'
      );
      expect(mobileLogo.get('img.dark\\:block').attributes('src')).toBe(
        logoDark || '/logo.svg'
      );
      expect(column.get('[data-testid="auth-form"]').exists()).toBe(true);
    }
  );
});
