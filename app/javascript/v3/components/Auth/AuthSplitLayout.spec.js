import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import loginHero from 'assets/images/auth/login-hero.png';
import AuthSplitLayout from './AuthSplitLayout.vue';

describe('AuthSplitLayout', () => {
  let wrapper;
  afterEach(() => wrapper?.unmount());

  it.each([true, false])(
    'reserves the actual footer height outside the scroll region with 24px bottom clearance (footer=%s)',
    withFooter => {
      const store = createStore({
        getters: { 'globalConfig/get': () => ({ logo: '/logo.svg' }) },
      });
      wrapper = mount(AuthSplitLayout, {
        props: { title: 'Welcome', subtitle: 'Get started', onboarding: true },
        slots: {
          default:
            '<form id="onboarding-form"><a href="#guide">Guide</a></form>',
          ...(withFooter && {
            footer: '<button form="onboarding-form">Continue</button>',
          }),
        },
        global: { plugins: [store] },
      });
      expect(wrapper.get('main').classes()).toContain('h-dvh');
      const column = wrapper.get('[data-testid="onboarding-column"]');
      expect(column.classes()).toContain(
        'pb-[max(1.5rem,env(safe-area-inset-bottom))]'
      );
      const scroller = wrapper.get('[data-testid="onboarding-scroll-content"]');
      expect(scroller.classes()).toEqual(
        expect.arrayContaining(['min-h-0', 'overflow-y-auto', 'pb-4'])
      );
      expect(scroller.get('a').text()).toBe('Guide');
      expect(wrapper.find('footer').exists()).toBe(withFooter);
      if (withFooter) {
        const footer = wrapper.get('footer');
        expect(scroller.element.parentElement).toBe(
          footer.element.parentElement
        );
        expect(scroller.element.nextElementSibling).toBe(footer.element);
        expect(footer.classes()).toEqual(
          expect.arrayContaining(['shrink-0', 'backdrop-blur-md'])
        );
        expect(scroller.find('button').exists()).toBe(false);
        expect(footer.get('button').element.form).toBe(
          scroller.get('form').element
        );
      }
    }
  );

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
