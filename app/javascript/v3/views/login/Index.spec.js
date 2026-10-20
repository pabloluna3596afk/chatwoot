import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import { login } from '../../api/auth';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/login.json';
import es from 'dashboard/i18n/locale/es/login.json';
import Login from './Index.vue';
import AuthSplitLayout from '../../components/Auth/AuthSplitLayout.vue';

vi.mock('../../api/auth', () => ({ login: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/helper/AnalyticsHelper', () => ({
  default: { track: vi.fn() },
}));
vi.mock('dashboard/components/auth/MfaVerification.vue', () => ({
  default: {
    name: 'MfaVerification',
    props: ['mfaToken'],
    emits: ['verified', 'cancel'],
    template: '<div />',
  },
}));
vi.mock('dashboard/components/auth/SessionLimitOverlay.vue', () => ({
  default: {
    name: 'SessionLimitOverlay',
    props: ['sessions'],
    emits: ['revoke', 'revokeAll', 'cancel'],
    template: '<div />',
  },
}));

const originalPlugins = config.global.plugins;
const originalStubs = config.global.stubs;
const originalChatwootConfig = window.chatwootConfig;
let wrapper;
let router;
let i18n;
let globalConfig;

beforeEach(async () => {
  window.chatwootConfig = {
    signupEnabled: 'true',
    allowedLoginMethods: ['email', 'google_oauth', 'saml'],
    googleOAuthClientId: 'client-id',
    googleOAuthCallbackUrl: 'https://example.com/auth/google_oauth2/callback',
  };
  globalConfig = {
    installationName: 'ChatHub',
    logo: '/logo.svg',
    logoDark: '/logo-dark.svg',
    deploymentEnv: 'staging',
    disableUserProfileUpdate: false,
  };
  const store = createStore({
    getters: { 'globalConfig/get': () => globalConfig },
  });
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      '/app/login',
      '/app/auth/signup',
      '/app/auth/reset/password',
      '/app/login/sso',
    ].map(path => ({ path, component: { template: '<div />' } })),
  });
  await router.push('/app/login');
  await router.isReady();
  i18n = createI18n({ legacy: false, locale: 'en', messages: { en, es } });
  config.global.plugins = [store, router, i18n];
  config.global.stubs = { FluentIcon: true };
  login.mockResolvedValue(null);
});

afterEach(() => {
  wrapper?.unmount();
  config.global.plugins = originalPlugins;
  config.global.stubs = originalStubs;
  window.chatwootConfig = originalChatwootConfig;
});

describe('login', () => {
  it('renders the unchanged login content inside the shared auth layout', () => {
    wrapper = mount(Login);
    const layout = wrapper.getComponent(AuthSplitLayout);
    expect(layout.props()).toMatchObject({
      title: en.LOGIN.MARKETING.TITLE,
      subtitle: en.LOGIN.MARKETING.SUBTITLE,
    });
    expect(layout.get('[data-testid="auth-marketing-title"]').text()).toBe(
      en.LOGIN.MARKETING.TITLE
    );
    expect(layout.get('form').exists()).toBe(true);
    expect(wrapper.get('input[type="email"]').classes()).toContain('h-14');
    expect(wrapper.get('button[type="submit"]').classes()).toContain('h-14');
  });

  it.each(['en', 'es'])('renders the form and links in %s', locale => {
    i18n.global.locale.value = locale;
    const messages = { en, es }[locale].LOGIN;
    wrapper = mount(Login);

    expect(wrapper.get('h1').text()).toBe(messages.TITLE);
    expect(wrapper.get('input[type="email"]').attributes('aria-label')).toBe(
      messages.EMAIL.LABEL
    );
    expect(wrapper.get('input[type="password"]').attributes('aria-label')).toBe(
      messages.PASSWORD.LABEL
    );
    expect(
      wrapper.findAll('label').every(label => label.classes('sr-only'))
    ).toBe(true);
    expect(wrapper.get('button[type="submit"]').text()).toBe(messages.SUBMIT);
    expect(wrapper.get('a[href="/app/auth/signup"]').text()).toBe(
      messages.CREATE_NEW_ACCOUNT
    );
    expect(wrapper.get('a[href="/app/auth/reset/password"]').text()).toBe(
      messages.FORGOT_PASSWORD
    );
    expect(wrapper.get('a[href="/app/login/sso"]').text()).toBe(
      messages.SAML.LABEL
    );
    expect(wrapper.get('a[href^="https://accounts.google.com"]').text()).toBe(
      messages.OAUTH.GOOGLE_LOGIN
    );
    expect(wrapper.text()).toContain(messages.STAGING_LABEL);
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('hides signup, password reset and alternative methods when disabled', () => {
    window.chatwootConfig.signupEnabled = 'false';
    window.chatwootConfig.allowedLoginMethods = ['email'];
    globalConfig.disableUserProfileUpdate = true;
    globalConfig.deploymentEnv = 'production';
    wrapper = mount(Login);

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('.section-separator').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(en.LOGIN.STAGING_LABEL);
  });

  it.each(['en', 'es'])(
    'shows the divider, Google and SSO together in %s',
    async locale => {
      i18n.global.locale.value = locale;
      window.chatwootConfig.allowedLoginMethods = [
        'email',
        'google_oauth',
        'saml',
      ];
      window.chatwootConfig.googleOAuthClientId = 'client-id';
      wrapper = mount(Login);

      const messages = { en, es }[locale].LOGIN;
      const divider = wrapper.get('.section-separator');
      const google = wrapper.get('a[href^="https://accounts.google.com"]');
      const sso = wrapper.get('a[href="/app/login/sso"]');
      expect(divider.text()).toBe(messages.OR);
      expect(divider.find('[aria-hidden="true"] .border-t').exists()).toBe(
        true
      );
      expect(google.text()).toBe(messages.OAUTH.GOOGLE_LOGIN);
      expect(google.find('.i-logos-google-icon').exists()).toBe(true);
      const googleUrl = new URL(google.attributes('href'));
      expect(googleUrl.searchParams.get('client_id')).toBe('client-id');
      expect(googleUrl.searchParams.get('redirect_uri')).toBe(
        window.chatwootConfig.googleOAuthCallbackUrl
      );
      expect(sso.text()).toBe(messages.SAML.LABEL);
      expect(divider.element.compareDocumentPosition(google.element)).toBe(
        Node.DOCUMENT_POSITION_FOLLOWING
      );
      expect(google.element.compareDocumentPosition(sso.element)).toBe(
        Node.DOCUMENT_POSITION_FOLLOWING
      );

      await sso.trigger('click');
      await flushPromises();
      expect(router.currentRoute.value.path).toBe('/app/login/sso');
    }
  );

  it('does not show Google or a divider without a configured client', () => {
    window.chatwootConfig.allowedLoginMethods = ['email', 'google_oauth'];
    window.chatwootConfig.googleOAuthClientId = '';
    wrapper = mount(Login);

    expect(
      wrapper.find('a[href^="https://accounts.google.com"]').exists()
    ).toBe(false);
    expect(wrapper.find('.section-separator').exists()).toBe(false);
  });

  it('keeps the password visibility toggle', async () => {
    wrapper = mount(Login);
    await wrapper.get('input[name="password"]').setValue('secret');
    await wrapper.get('button[aria-pressed]').trigger('click');

    expect(wrapper.get('input[name="password"]').attributes('type')).toBe(
      'text'
    );
    expect(wrapper.get('button[aria-pressed]').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(wrapper.get('input[name="password"]').element.value).toBe('secret');
    await wrapper.get('button[aria-pressed]').trigger('click');
    expect(wrapper.get('input[name="password"]').attributes('type')).toBe(
      'password'
    );
    expect(wrapper.get('button[aria-pressed]').attributes('aria-pressed')).toBe(
      'false'
    );
  });

  it('submits credentials and centers a spinner while loading', async () => {
    login.mockImplementation(() => new Promise(() => {}));
    wrapper = mount(Login);
    await wrapper.get('input[type="email"]').setValue('agent@example.com');
    await wrapper.get('input[type="password"]').setValue('secret');
    await wrapper.get('form').trigger('submit');

    expect(login).toHaveBeenCalledWith({
      email: 'agent@example.com',
      password: 'secret',
      sso_auth_token: '',
      ssoAccountId: '',
      ssoConversationId: '',
    });
    const submit = wrapper.get('button[type="submit"]');
    expect(submit.attributes('disabled')).toBeDefined();
    expect(submit.attributes('aria-busy')).toBe('true');
    expect(submit.find('svg.animate-spin').exists()).toBe(true);
    expect(submit.text()).toBe('');
  });

  it('shows an authentication error and enables the form again', async () => {
    login.mockRejectedValue(new Error('Incorrect credentials'));
    wrapper = mount(Login);
    await wrapper.get('input[type="email"]').setValue('agent@example.com');
    await wrapper.get('input[type="password"]').setValue('secret');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Incorrect credentials');
    expect(wrapper.get('button[type="submit"]').attributes('disabled')).toBe(
      undefined
    );
  });

  it('retains MFA verification and cancellation', async () => {
    login.mockResolvedValue({ mfaRequired: true, mfaToken: 'mfa-token' });
    wrapper = mount(Login);
    await wrapper.get('input[type="email"]').setValue('agent@example.com');
    await wrapper.get('input[type="password"]').setValue('secret');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    const mfa = wrapper.getComponent({ name: 'MfaVerification' });
    expect(mfa.props('mfaToken')).toBe('mfa-token');
    expect(wrapper.find('form').exists()).toBe(false);
    mfa.vm.$emit('cancel');
    await flushPromises();
    expect(wrapper.get('input[type="password"]').element.value).toBe('');
    expect(wrapper.get('input[type="email"]').element.value).toBe(
      'agent@example.com'
    );
  });

  it('retains session revocation and cancellation', async () => {
    const sessions = [{ id: 42 }];
    login.mockResolvedValue({ sessionsLimitReached: true, sessions });
    wrapper = mount(Login);
    await wrapper.get('input[type="email"]').setValue('agent@example.com');
    await wrapper.get('input[type="password"]').setValue('secret');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    const overlay = wrapper.getComponent({ name: 'SessionLimitOverlay' });
    expect(overlay.props('sessions')).toEqual(sessions);
    overlay.vm.$emit('revoke', 42);
    await flushPromises();
    expect(login).toHaveBeenLastCalledWith(
      expect.objectContaining({ revoke_session_id: 42 })
    );
    wrapper.getComponent({ name: 'SessionLimitOverlay' }).vm.$emit('revokeAll');
    await flushPromises();
    expect(login).toHaveBeenLastCalledWith(
      expect.objectContaining({ revoke_all_sessions: true })
    );
    wrapper.getComponent({ name: 'SessionLimitOverlay' }).vm.$emit('cancel');
    await flushPromises();
    expect(wrapper.get('input[type="password"]').element.value).toBe('');
  });

  it('retains automatic SSO login and encoded email parameters', async () => {
    wrapper = mount(Login, {
      props: {
        email: 'agent%40example.com',
        ssoAuthToken: 'sso-token',
        ssoAccountId: '7',
        ssoConversationId: '13',
      },
    });
    await flushPromises();

    expect(login).toHaveBeenCalledWith({
      email: 'agent@example.com',
      password: '',
      sso_auth_token: 'sso-token',
      ssoAccountId: '7',
      ssoConversationId: '13',
    });
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.find('svg.animate-spin').exists()).toBe(true);
  });

  it('shows OAuth errors and removes only the error query parameter', async () => {
    await router.replace('/app/login?error=no-account-found&email=agent');
    wrapper = mount(Login, { props: { authError: 'no-account-found' } });
    await flushPromises();
    await new Promise(resolve => {
      setTimeout(resolve, 10);
    });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(en.LOGIN.OAUTH.NO_ACCOUNT_FOUND, {
      duration: 6000,
    });
    expect(router.currentRoute.value.query).toEqual({ email: 'agent' });
  });
});
