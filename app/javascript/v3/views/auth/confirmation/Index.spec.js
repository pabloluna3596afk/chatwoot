import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { reactive, nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import es from 'dashboard/i18n/locale/es/signup.json';
import en from 'dashboard/i18n/locale/en/signup.json';
import Index from './Index.vue';

const { post, execute, reset } = vi.hoisted(() => ({
  post: vi.fn(),
  execute: vi.fn(),
  reset: vi.fn(),
}));
let globalConfig;

vi.mock('v3/api/apiClient', () => ({ default: { post } }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { 'globalConfig/get': globalConfig } }),
}));

describe('Email confirmation', () => {
  let wrapper;
  let i18n;

  beforeEach(() => {
    vi.stubGlobal('location', '/app/auth/confirmation');
    globalConfig = reactive({ hCaptchaSiteKey: '' });
    i18n = createI18n({ legacy: false, locale: 'es', messages: { es, en } });
    post.mockRejectedValueOnce({
      response: { status: 422, data: { message: 'Invalid token' } },
    });
    wrapper = mount(Index, {
      props: { confirmationToken: 'invalid-token' },
      global: {
        plugins: [i18n],
        stubs: {
          RouterLink: RouterLinkStub,
          NextButton: false,
          VueHcaptcha: {
            name: 'VueHcaptcha',
            methods: { execute, reset },
            template: '<div />',
          },
        },
      },
    });
  });

  afterEach(() => {
    wrapper.unmount();
    vi.unstubAllGlobals();
  });

  it('shows a translated recovery state instead of redirecting for an invalid token', async () => {
    await flushPromises();
    expect(post).toHaveBeenCalledWith('auth/confirmation', {
      confirmation_token: 'invalid-token',
    });
    expect(window.location).toBe('/app/auth/confirmation');
    expect(wrapper.get('[role="alert"]').text()).toContain(
      es.REGISTER.CONFIRMATION.ERROR_DESCRIPTION
    );
    expect(wrapper.getComponent(RouterLinkStub).props('to')).toEqual({
      name: 'login',
    });
    expect(wrapper.getComponent(RouterLinkStub).text()).toBe('Entrar');
    expect(wrapper.get('button[type="submit"]').text()).toBe(
      'Reenviar correo de confirmación'
    );

    i18n.global.locale.value = 'en';
    await nextTick();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      en.REGISTER.CONFIRMATION.ERROR_DESCRIPTION
    );
  });

  it('resends through the existing endpoint and always uses neutral success copy', async () => {
    await flushPromises();
    await wrapper.get('input[name="email"]').setValue('ana@gmail.com');
    post.mockResolvedValueOnce({ status: 200 });
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(post).toHaveBeenLastCalledWith('resend_confirmation', {
      email: 'ana@gmail.com',
      h_captcha_client_response: '',
    });
    expect(wrapper.get('[role="status"]').text()).toBe(
      es.REGISTER.VERIFY_EMAIL.RESEND_SUCCESS
    );
    expect(window.location).toBe('/app/auth/confirmation');
  });

  it('does not send an empty or invalid email', async () => {
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await wrapper.get('input[name="email"]').setValue('invalid-email');
    await wrapper.get('form').trigger('submit');
    expect(post).toHaveBeenCalledOnce();
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
  });

  it('shows resend failure and allows retry', async () => {
    await flushPromises();
    await wrapper.get('input[name="email"]').setValue('ana@gmail.com');
    post.mockRejectedValueOnce(new Error('Network Error'));
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="status"]').text()).toBe(
      es.REGISTER.VERIFY_EMAIL.RESEND_ERROR
    );
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();

    post.mockResolvedValueOnce({ status: 200 });
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="status"]').text()).toBe(
      es.REGISTER.VERIFY_EMAIL.RESEND_SUCCESS
    );
  });

  it('waits for captcha, prevents duplicate submissions and clears the token after resend', async () => {
    await flushPromises();
    globalConfig.hCaptchaSiteKey = 'site-key';
    await nextTick();
    await wrapper.get('input[name="email"]').setValue('ana@gmail.com');
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    expect(execute).toHaveBeenCalledOnce();
    expect(post).toHaveBeenCalledOnce();

    post.mockResolvedValueOnce({ status: 200 });
    wrapper
      .getComponent({ name: 'VueHcaptcha' })
      .vm.$emit('verify', 'captcha-token');
    await flushPromises();
    expect(post).toHaveBeenLastCalledWith('resend_confirmation', {
      email: 'ana@gmail.com',
      h_captcha_client_response: 'captcha-token',
    });
    expect(reset).toHaveBeenCalledOnce();
    expect(wrapper.get('[role="status"]').text()).toBe(
      es.REGISTER.VERIFY_EMAIL.RESEND_SUCCESS
    );
  });

  it('explains a captcha failure and allows retry', async () => {
    await flushPromises();
    globalConfig.hCaptchaSiteKey = 'site-key';
    await nextTick();
    await wrapper.get('input[name="email"]').setValue('ana@gmail.com');
    await wrapper.get('form').trigger('submit');
    wrapper.getComponent({ name: 'VueHcaptcha' }).vm.$emit('error');
    await flushPromises();
    expect(wrapper.get('[role="status"]').text()).toBe(
      es.REGISTER.CAPTCHA.ERROR
    );
    expect(reset).toHaveBeenCalledOnce();
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('redirects after successful confirmation and preserves authentication handling', async () => {
    await flushPromises();
    wrapper.unmount();
    post.mockResolvedValueOnce({
      headers: { expiry: Math.floor(Date.now() / 1000) + 3600 },
      data: { data: { id: 1 } },
    });
    wrapper = mount(Index, {
      props: { confirmationToken: 'valid-token' },
      global: { plugins: [i18n] },
    });
    await flushPromises();
    expect(post).toHaveBeenLastCalledWith('auth/confirmation', {
      confirmation_token: 'valid-token',
    });
    expect(window.location).toBe('/app/');
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it.each(['Failure', 'Already confirmed'])(
    'also offers recovery for %s',
    async message => {
      await flushPromises();
      wrapper.unmount();
      post.mockRejectedValueOnce({
        response: { status: 422, data: { message } },
      });
      wrapper = mount(Index, {
        props: { confirmationToken: 'expired-or-used-token' },
        global: {
          plugins: [i18n],
          stubs: { RouterLink: RouterLinkStub, NextButton: false },
        },
      });
      await flushPromises();
      expect(window.location).toBe('/app/auth/confirmation');
      expect(wrapper.get('[role="alert"]').text()).toContain(
        es.REGISTER.CONFIRMATION.ERROR_DESCRIPTION
      );
      expect(wrapper.getComponent(RouterLinkStub).props('to')).toEqual({
        name: 'login',
      });
      expect(wrapper.get('button[type="submit"]').text()).toBe(
        es.REGISTER.CONFIRMATION.RESEND
      );
    }
  );
});
