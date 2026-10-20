import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import login from 'dashboard/i18n/locale/en/login.json';
import signup from 'dashboard/i18n/locale/en/signup.json';
import setNewPassword from 'dashboard/i18n/locale/en/setNewPassword.json';
import SignupForm from './signup/components/Signup/Form.vue';
import Saml from '../login/Saml.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../api/auth', () => ({ register: vi.fn() }));

describe('shared auth form compatibility', () => {
  const originalChatwootConfig = window.chatwootConfig;
  let wrapper;
  let plugins;

  beforeEach(async () => {
    window.chatwootConfig = { allowedLoginMethods: ['email'] };
    const store = createStore({
      getters: {
        'globalConfig/get': () => ({
          logo: '/logo.svg',
          installationName: 'ChatHub',
          termsURL: 'https://example.com/terms',
          privacyURL: 'https://example.com/privacy',
        }),
      },
    });
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/app/login', component: { template: '<div />' } }],
    });
    await router.push('/app/login');
    await router.isReady();
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: { ...login, ...signup, ...setNewPassword } },
    });
    plugins = [store, router, i18n];
  });

  afterEach(() => {
    wrapper?.unmount();
    window.chatwootConfig = originalChatwootConfig;
  });

  it.each([
    ['signup', SignupForm],
    ['SAML', Saml],
  ])(
    'keeps accessible labels and the intended field variant in %s',
    (name, view) => {
      wrapper = mount(view, {
        global: { plugins, stubs: { Button: false, NextButton: false } },
      });

      const labels = wrapper.findAll('label');
      expect(labels.length).toBe(view === SignupForm ? 2 : 1);
      labels.forEach(label => {
        expect(label.text()).not.toBe('');
        expect(label.classes('sr-only')).toBe(view === SignupForm);
        const input = wrapper.get(`input[id="${label.attributes('for')}"]`);
        expect(input.classes()).toEqual(
          expect.arrayContaining([
            ...(view === SignupForm
              ? ['rounded-xl', 'bg-n-solid-1', 'px-4', 'h-14', 'reset-base']
              : [
                  'rounded-md',
                  'shadow-sm',
                  'bg-n-alpha-black2',
                  'px-3',
                  'sm:text-sm',
                  'sm:leading-6',
                ]),
            'py-3',
          ])
        );
        expect(input.classes('h-14')).toBe(view === SignupForm);
        expect(input.classes('reset-base')).toBe(view === SignupForm);
      });
    }
  );

  it('keeps the signup password eye with outlined spacing', async () => {
    wrapper = mount(SignupForm, {
      global: { plugins, stubs: { Button: false, NextButton: false } },
    });
    const input = wrapper.get('input[name="password"]');
    const button = wrapper.get('button[aria-pressed]');
    expect(input.classes('pe-12')).toBe(true);
    expect(button.classes('!px-3')).toBe(true);
    expect(button.classes('!h-full')).toBe(true);
    await input.setValue('Strong!Password1');
    await button.trigger('click');
    expect(input.attributes('type')).toBe('text');
    await button.trigger('click');
    expect(input.attributes('type')).toBe('password');
    expect(input.element.value).toBe('Strong!Password1');
  });

  it('preserves the SAML POST fields and validation', async () => {
    wrapper = mount(Saml, {
      props: { target: 'mobile' },
      global: { plugins, stubs: { Button: false, NextButton: false } },
    });
    const form = wrapper.get('form');
    const input = wrapper.get('input[name="email"]');
    expect(form.attributes('method')).toBe('POST');
    expect(form.attributes('action')).toBe('/api/v1/auth/saml_login');
    expect(wrapper.get('input[name="target"]').element.value).toBe('mobile');
    expect(wrapper.find('input[name="authenticity_token"]').exists()).toBe(
      true
    );
    expect(wrapper.find('button[aria-pressed]').exists()).toBe(false);
    await input.setValue('invalid-email');
    await flushPromises();
    expect(input.classes('error')).toBe(true);
    await input.setValue('agent@example.com');
    await flushPromises();
    expect(input.classes('error')).toBe(false);
  });
});
