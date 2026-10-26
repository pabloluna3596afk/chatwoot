import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import MfaEnforcedSetup from './MfaEnforcedSetup.vue';
import en from 'dashboard/i18n/locale/en/mfa.json';
import es from 'dashboard/i18n/locale/es/mfa.json';

const { post, setAuthCredentials } = vi.hoisted(() => ({
  post: vi.fn(),
  setAuthCredentials: vi.fn(),
}));

vi.mock('axios', () => ({ default: { post } }));
vi.mock('dashboard/store/utils/api', () => ({
  parseAPIErrorResponse: vi.fn(() => 'invalid code'),
  setAuthCredentials,
}));
vi.mock(
  'dashboard/routes/dashboard/settings/profile/MfaSetupWizard.vue',
  () => ({
    default: {
      name: 'MfaSetupWizard',
      props: ['provisioningUri', 'secretKey', 'backupCodes'],
      emits: ['verify', 'complete'],
      template:
        '<button data-testid="verify" @click="$emit(\'verify\', \'123456\')" />',
    },
  })
);

describe('MfaEnforcedSetup', () => {
  const mountComponent = locale =>
    mount(MfaEnforcedSetup, {
      props: {
        mfaSetupToken: 'setup-token',
        provisioningUrl: 'otpauth://setup',
        secret: 'secret-value',
      },
      global: {
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
      },
    });

  beforeEach(() => {
    post.mockReset();
    setAuthCredentials.mockReset();
  });

  it.each([
    ['en', 'Set up two-factor authentication'],
    ['es', 'Configura la autenticación de dos factores'],
  ])('renders the required setup message in %s', (locale, title) => {
    const wrapper = mountComponent(locale);

    expect(wrapper.text()).toContain(title);
    expect(
      wrapper.getComponent({ name: 'MfaSetupWizard' }).props()
    ).toMatchObject({
      provisioningUri: 'otpauth://setup',
      secretKey: 'secret-value',
      backupCodes: [],
    });
  });

  it('verifies the setup code, stores credentials, and returns backup codes', async () => {
    const response = {
      data: { data: { access_token: 'token' }, backup_codes: ['backup'] },
    };
    post.mockResolvedValue(response);
    const wrapper = mountComponent('en');

    await wrapper.get('[data-testid="verify"]').trigger('click');
    await flushPromises();

    expect(post).toHaveBeenCalledWith('/auth/sign_in', {
      mfa_setup_token: 'setup-token',
      otp_code: '123456',
    });
    expect(
      wrapper.getComponent({ name: 'MfaSetupWizard' }).props('backupCodes')
    ).toEqual(['backup']);
    wrapper.getComponent({ name: 'MfaSetupWizard' }).vm.$emit('complete');
    expect(setAuthCredentials).toHaveBeenCalledWith(response);
    expect(wrapper.emitted('verified')).toBeTruthy();
  });
});
