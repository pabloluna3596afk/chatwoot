import { flushPromises, mount } from '@vue/test-utils';
import { reactive, nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import es from 'dashboard/i18n/locale/es/signup.json';
import login from 'dashboard/i18n/locale/es/login.json';
import Form from './Form.vue';

const { post, push, execute, reset } = vi.hoisted(() => ({
  post: vi.fn(),
  push: vi.fn(),
  execute: vi.fn(),
  reset: vi.fn(),
}));
let globalConfig;

vi.mock('v3/api/apiClient', () => ({ default: { post } }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { 'globalConfig/get': globalConfig } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('Signup Form', () => {
  let wrapper;

  beforeEach(async () => {
    window.chatwootConfig = reactive({
      allowedLoginMethods: ['email'],
      googleOAuthClientId: '',
    });
    globalConfig = reactive({ hCaptchaSiteKey: '' });
    wrapper = mount(Form, {
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'es',
            messages: { es: { ...es, ...login } },
          }),
        ],
        stubs: {
          NextButton: false,
          VueHcaptcha: {
            name: 'VueHcaptcha',
            methods: { execute, reset },
            template: '<div />',
          },
        },
      },
    });
    await wrapper.get('input[name="email_address"]').setValue('ana@gmail.com');
    await wrapper.get('input[name="password"]').setValue('Secure123!');
  });

  afterEach(() => {
    wrapper.unmount();
    window.chatwootConfig = {};
  });

  it('accepts Gmail and keeps the registration request and verification route', async () => {
    post.mockResolvedValueOnce({ data: { email: 'ana@gmail.com' } });
    expect(
      wrapper.get('[data-testid="submit_button"]').attributes('disabled')
    ).toBeUndefined();
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(post).toHaveBeenCalledWith('api/v1/accounts.json', {
      account_name: 'Gmail',
      user_full_name: 'Ana',
      email: 'ana@gmail.com',
      password: 'Secure123!',
      h_captcha_client_response: '',
    });
    expect(push).toHaveBeenCalledWith({
      name: 'auth_verify_email',
      state: { email: 'ana@gmail.com' },
    });
  });

  it('submits disposable email to the server and displays its rejection', async () => {
    const message = 'No se permiten correos electrónicos desechables.';
    await wrapper
      .get('input[name="email_address"]')
      .setValue('ana@mailinator.com');
    post.mockRejectedValueOnce({
      response: { status: 403, data: { message } },
    });
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(post).toHaveBeenCalledWith(
      'api/v1/accounts.json',
      expect.objectContaining({ email: 'ana@mailinator.com' })
    );
    expect(useAlert).toHaveBeenCalledExactlyOnceWith(message);
    expect(push).not.toHaveBeenCalled();
    expect(
      wrapper.get('[data-testid="submit_button"]').attributes('disabled')
    ).toBeUndefined();
  });

  it.each([
    new Error('Network Error'),
    { response: { status: 500 } },
    { response: { data: { message: {} } } },
  ])(
    'uses the translated generic message for an error without usable payload: %j',
    async error => {
      post.mockRejectedValueOnce(error);
      await wrapper.get('form').trigger('submit');
      await flushPromises();

      expect(useAlert).toHaveBeenCalledExactlyOnceWith(
        'No pudimos completar la acción. Inténtalo de nuevo.'
      );
      expect(push).not.toHaveBeenCalled();
    }
  );

  it('translates a server captcha rejection and allows another attempt', async () => {
    globalConfig.hCaptchaSiteKey = 'site-key';
    await nextTick();
    post.mockRejectedValueOnce({
      response: { status: 422, data: { error: 'Invalid Captcha' } },
    });
    await wrapper.get('form').trigger('submit');
    expect(execute).toHaveBeenCalledOnce();
    expect(post).not.toHaveBeenCalled();
    wrapper
      .getComponent({ name: 'VueHcaptcha' })
      .vm.$emit('verify', 'captcha-token');
    await flushPromises();

    expect(post).toHaveBeenCalledWith(
      'api/v1/accounts.json',
      expect.objectContaining({ h_captcha_client_response: 'captcha-token' })
    );
    expect(useAlert).toHaveBeenCalledExactlyOnceWith(es.REGISTER.CAPTCHA.ERROR);
    expect(reset).toHaveBeenCalledOnce();
    expect(push).not.toHaveBeenCalled();
    expect(
      wrapper.get('[data-testid="submit_button"]').attributes('disabled')
    ).toBeUndefined();
  });

  it.each(['error', 'expired', 'challenge-expired', 'closed'])(
    'explains captcha %s and re-enables submission',
    async event => {
      globalConfig.hCaptchaSiteKey = 'site-key';
      await nextTick();
      await wrapper.get('form').trigger('submit');
      wrapper.getComponent({ name: 'VueHcaptcha' }).vm.$emit(event);
      await flushPromises();

      expect(useAlert).toHaveBeenCalledExactlyOnceWith(
        es.REGISTER.CAPTCHA.ERROR
      );
      expect(reset).toHaveBeenCalledOnce();
      expect(post).not.toHaveBeenCalled();
      expect(
        wrapper.get('[data-testid="submit_button"]').attributes('disabled')
      ).toBeUndefined();
    }
  );

  it('keeps invalid email blocked before making a request', async () => {
    await wrapper.get('input[name="email_address"]').setValue('invalid-email');
    await wrapper.get('form').trigger('submit');
    expect(post).not.toHaveBeenCalled();
    expect(
      wrapper.get('[data-testid="submit_button"]').attributes('disabled')
    ).toBeDefined();
  });

  it.each([
    '',
    'short',
    'lowercase1!',
    'UPPERCASE1!',
    'NoNumbers!',
    'NoSpecial1',
  ])('blocks invalid password %j before making a request', async password => {
    await wrapper.get('input[name="password"]').setValue(password);
    await wrapper.get('form').trigger('submit');
    expect(post).not.toHaveBeenCalled();
    expect(push).not.toHaveBeenCalled();
    expect(wrapper.get('[data-testid="submit_button"]').element.disabled).toBe(
      true
    );
  });

  it('keeps translated requirements below the password and updates each check live', async () => {
    const input = wrapper.get('input[name="password"]');
    const requirements = wrapper.get('#signup-password-requirements');
    expect(input.attributes('aria-describedby')).toBe(
      'signup-password-requirements'
    );
    expect(requirements.findAll('li')).toHaveLength(5);
    expect(requirements.text()).toContain(
      es.REGISTER.PASSWORD.REQUIREMENTS_LENGTH
    );
    expect(requirements.classes()).toContain('w-full');
    expect(requirements.classes()).not.toContain('absolute');
    await input.setValue('');
    expect(requirements.findAll('.i-lucide-circle-check-big')).toHaveLength(0);
    await input.setValue('a');
    expect(requirements.findAll('.i-lucide-circle-check-big')).toHaveLength(1);
    await input.setValue('aA');
    expect(requirements.findAll('.i-lucide-circle-check-big')).toHaveLength(2);
    await input.setValue('aA1');
    expect(requirements.findAll('.i-lucide-circle-check-big')).toHaveLength(3);
    await input.setValue('aA1!');
    expect(requirements.findAll('.i-lucide-circle-check-big')).toHaveLength(4);
    await input.setValue('aA1!xx');
    expect(
      requirements.findAll('.i-lucide-circle-check-big.text-n-teal-11')
    ).toHaveLength(5);
    await input.trigger('blur');
    expect(requirements.isVisible()).toBe(true);
  });

  it.each([
    [['email'], 'client-id', false],
    [['email', 'google_oauth'], '', false],
    [['email', 'google_oauth'], 'client-id', true],
  ])(
    'shows Google only for methods %j and client ID %j',
    async (methods, clientId, visible) => {
      window.chatwootConfig.allowedLoginMethods = methods;
      window.chatwootConfig.googleOAuthClientId = clientId;
      await nextTick();
      expect(
        wrapper.find('a[href^="https://accounts.google.com"]').exists()
      ).toBe(visible);
      expect(wrapper.text().includes(es.REGISTER.OAUTH.PASSWORD_NOTICE)).toBe(
        visible
      );
      expect(wrapper.find('.section-separator').exists()).toBe(visible);
      if (visible) {
        const divider = wrapper.get('.section-separator');
        expect(divider.text()).toBe(es.REGISTER.OR);
        expect(divider.classes()).toEqual(
          expect.arrayContaining([
            '[&_.border-t]:border-solid',
            '[&_.border-t]:border-n-slate-7',
            '[&_span]:text-n-slate-11',
          ])
        );
        expect(
          divider.get('[aria-hidden="true"] .border-t').classes()
        ).toContain('border-n-strong');
        expect(divider.get('span').classes()).toEqual(
          expect.arrayContaining(['bg-n-solid-1', 'dark:bg-n-background'])
        );
        expect(
          wrapper.get('a[href^="https://accounts.google.com"]').text()
        ).toBe('Registrarte con Google');
        expect(wrapper.text()).toContain(es.REGISTER.OR);
      }
    }
  );

  it('shows a spinner and blocks duplicate submissions while registering', async () => {
    post.mockReturnValueOnce(new Promise(() => {}));
    await wrapper.get('form').trigger('submit');
    const button = wrapper.get('[data-testid="submit_button"]');
    expect(button.attributes('aria-busy')).toBe('true');
    expect(button.element.disabled).toBe(true);
    expect(button.find('svg.animate-spin').exists()).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(post).toHaveBeenCalledOnce();
  });
});
