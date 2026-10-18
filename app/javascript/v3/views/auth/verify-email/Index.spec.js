import authEn from 'dashboard/i18n/locale/en/auth.json';
import authEs from 'dashboard/i18n/locale/es/auth.json';
import { flushPromises, mount } from '@vue/test-utils';
import { nextTick, reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/signup.json';
import es from 'dashboard/i18n/locale/es/signup.json';
import AuthSplitLayout from '../../../components/Auth/AuthSplitLayout.vue';
import VerifyEmail from './Index.vue';

const { post, execute, reset } = vi.hoisted(() => ({
  post: vi.fn(),
  execute: vi.fn(),
  reset: vi.fn(),
}));
vi.mock('v3/api/apiClient', () => ({ default: { post } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('Verify email page', () => {
  let wrapper;
  let globalConfig;
  let router;
  let mountOptions;
  let i18n;

  beforeEach(async () => {
    globalConfig = reactive({
      installationName: 'ChatHub',
      logo: '/logo.svg',
      hCaptchaSiteKey: '',
    });
    const store = createStore({
      getters: { 'globalConfig/get': () => globalConfig },
    });
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/app/auth/verify-email', component: { template: '<div />' } },
        {
          path: '/app/login',
          name: 'login',
          component: { template: '<div />' },
        },
      ],
    });
    await router.push('/app/auth/verify-email');
    await router.isReady();
    i18n = createI18n({
      legacy: false,
      locale: 'es',
      messages: { en: { ...en, ...authEn }, es: { ...es, ...authEs } },
    });
    mountOptions = {
      props: { email: 'ana@gmail.com' },
      global: {
        plugins: [store, router, i18n],
        stubs: {
          VueHcaptcha: {
            name: 'VueHcaptcha',
            methods: { execute, reset },
            template: '<div />',
          },
        },
      },
    };
  });

  afterEach(() => wrapper?.unmount());

  it.each(['en', 'es'])(
    'renders the shared layout and resend action in %s',
    locale => {
      i18n.global.locale.value = locale;
      const messages = { en, es }[locale].REGISTER;
      wrapper = mount(VerifyEmail, mountOptions);
      expect(wrapper.getComponent(AuthSplitLayout).exists()).toBe(true);
      expect(wrapper.get('h1').text()).toBe(messages.VERIFY_EMAIL.TITLE);
      expect(wrapper.text()).toContain('ana@gmail.com');
      expect(wrapper.get('.i-lucide-mail').attributes('aria-hidden')).toBe(
        'true'
      );
      const button = wrapper.get('[data-testid="resend_email_button"]');
      expect(button.text()).toBe(messages.VERIFY_EMAIL.RESEND);
      expect(button.classes()).toEqual(
        expect.arrayContaining(['min-h-12', 'rounded-xl'])
      );
      expect(wrapper.get('a[href="/app/login"]').text()).toBe(messages.SIGN_IN);
      expect(wrapper.findComponent({ name: 'VueHcaptcha' }).exists()).toBe(
        false
      );
    }
  );

  it('resends through the existing endpoint with a neutral success message', async () => {
    post.mockResolvedValueOnce({ status: 200 });
    wrapper = mount(VerifyEmail, mountOptions);
    await wrapper.get('[data-testid="resend_email_button"]').trigger('click');
    await flushPromises();
    expect(post).toHaveBeenCalledExactlyOnceWith('resend_confirmation', {
      email: 'ana@gmail.com',
      h_captcha_client_response: '',
    });
    expect(useAlert).toHaveBeenCalledExactlyOnceWith(
      es.REGISTER.VERIFY_EMAIL.RESEND_SUCCESS
    );
    expect(router.currentRoute.value.path).toBe('/app/auth/verify-email');
  });

  it('keeps the spinner and prevents duplicate resend requests while loading', async () => {
    post.mockReturnValueOnce(new Promise(() => {}));
    wrapper = mount(VerifyEmail, mountOptions);
    const button = wrapper.get('[data-testid="resend_email_button"]');
    await button.trigger('click');
    expect(button.attributes('aria-busy')).toBe('true');
    expect(button.element.disabled).toBe(true);
    expect(button.find('svg.animate-spin').exists()).toBe(true);
    await button.trigger('click');
    expect(post).toHaveBeenCalledOnce();
  });

  it('reports resend errors and permits retry', async () => {
    post.mockRejectedValueOnce(new Error('Network Error'));
    wrapper = mount(VerifyEmail, mountOptions);
    const button = wrapper.get('[data-testid="resend_email_button"]');
    await button.trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(
      es.REGISTER.VERIFY_EMAIL.RESEND_ERROR
    );
    expect(button.element.disabled).toBe(false);
    post.mockResolvedValueOnce({ status: 200 });
    await button.trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenLastCalledWith(
      es.REGISTER.VERIFY_EMAIL.RESEND_SUCCESS
    );
  });

  it('obtains and resets the captcha token around a resend', async () => {
    globalConfig.hCaptchaSiteKey = 'site-key';
    post.mockResolvedValueOnce({ status: 200 });
    wrapper = mount(VerifyEmail, mountOptions);
    await wrapper.get('[data-testid="resend_email_button"]').trigger('click');
    expect(execute).toHaveBeenCalledOnce();
    expect(post).not.toHaveBeenCalled();
    wrapper
      .getComponent({ name: 'VueHcaptcha' })
      .vm.$emit('verify', 'captcha-token');
    await flushPromises();
    expect(post).toHaveBeenCalledWith('resend_confirmation', {
      email: 'ana@gmail.com',
      h_captcha_client_response: 'captcha-token',
    });
    expect(reset).toHaveBeenCalledOnce();
  });

  it.each(['error', 'expired', 'challenge-expired', 'closed'])(
    'resets captcha after %s without sending a request',
    async event => {
      globalConfig.hCaptchaSiteKey = 'site-key';
      wrapper = mount(VerifyEmail, mountOptions);
      await wrapper.get('[data-testid="resend_email_button"]').trigger('click');
      wrapper.getComponent({ name: 'VueHcaptcha' }).vm.$emit(event);
      await nextTick();
      expect(reset).toHaveBeenCalledOnce();
      expect(post).not.toHaveBeenCalled();
    }
  );

  it('returns to login when opened without the registration email', async () => {
    wrapper = mount(VerifyEmail, { ...mountOptions, props: { email: '' } });
    await flushPromises();
    expect(router.currentRoute.value.name).toBe('login');
  });
});
